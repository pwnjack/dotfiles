#include <gio/gio.h>
#include <gio/gunixsocketaddress.h>
#include <glib/gstdio.h>
#include <stdlib.h>
#include <string.h>

#include "check.h"
#include "../hypr.h"

static int n_active, n_snap, n_disc, last_active = -1;
static WsState last;
static GSocketConnection *event_peer; /* server end of socket2 */
static GMutex lock;
static char last_dispatch[256];
static int n_events_conn;  /* event connections the fake server accepted */
static int snap_at_conn;   /* n_snap when the latest one arrived */
static gint big_reply; /* answer j/workspaces with more than HYPR_REPLY_MAX (atomic: read by the server thread) */

/* The fake command server holds the reply to `gate_req` until gate_open. */
static const char *gate_req;
static gboolean gate_open, gate_hit;
static HyprClient *c2;
static gboolean free_in_disc;

static void on_active(int a, void *d) { (void)d; n_active++; last_active = a; }
static void on_snapshot(const WsState *s, void *d) { (void)d; n_snap++; last = *s; }
static void on_disconnected(void *d) { (void)d; n_disc++; }
static void on_disconnected_free(void *d)
{
    (void)d;
    n_disc++;
    if (free_in_disc && c2) {
        HyprClient *x = c2;
        c2 = NULL;
        free_in_disc = FALSE;
        hypr_client_free(x);
    }
}

static void gate_set(const char *req, gboolean open)
{
    g_mutex_lock(&lock);
    gate_req = req;
    gate_open = open;
    gate_hit = FALSE;
    g_mutex_unlock(&lock);
}

static gboolean gate_was_hit(void)
{
    g_mutex_lock(&lock);
    gboolean hit = gate_hit;
    g_mutex_unlock(&lock);
    return hit;
}

static void gate_release(void)
{
    g_mutex_lock(&lock);
    gate_open = TRUE;
    g_mutex_unlock(&lock);
}

#define SPIN(cond, ms)                                                           \
    do {                                                                         \
        gint64 end_ = g_get_monotonic_time() + (ms) * 1000;                      \
        while (!(cond) && g_get_monotonic_time() < end_)                         \
            if (!g_main_context_iteration(NULL, FALSE))                          \
                g_usleep(1000);                                                  \
    } while (0)

/* Wait until *v stops changing for three retry periods (bounded). */
static void wait_stable(const int *v)
{
    for (int i = 0; i < 40; i++) {
        int seen = *v;
        SPIN(FALSE, 3 * HYPR_RETRY_MS);
        if (*v == seen)
            return;
    }
}

/* Command socket, in a worker thread: one request, one reply, close. */
static gboolean on_command(GThreadedSocketService *svc, GSocketConnection *conn, GObject *src,
                           gpointer d)
{
    (void)svc, (void)src, (void)d;
    char buf[512] = {0};
    gssize n = g_input_stream_read(g_io_stream_get_input_stream(G_IO_STREAM(conn)), buf,
                                   sizeof buf - 1, NULL, NULL);
    const char *reply = "unknown request";
    g_mutex_lock(&lock);
    gboolean gated = n > 0 && gate_req && !strcmp(buf, gate_req) && !gate_open;
    if (gated)
        gate_hit = TRUE;
    g_mutex_unlock(&lock);
    for (int i = 0; gated && i < 5000; i++) { /* held at most 5 s */
        g_usleep(1000);
        g_mutex_lock(&lock);
        gated = !gate_open;
        g_mutex_unlock(&lock);
    }
    if (n > 0) {
        if (!strcmp(buf, "j/workspaces") && g_atomic_int_get(&big_reply)) {
            /* Valid JSON padded past the cap: without HYPR_REPLY_MAX it would
             * parse and yield a snapshot, so this test guards the cap itself. */
            static const char head[] = "[{\"id\":1,\"windows\":2}";
            gsize len = 1024 * 1024 + 4096;
            char *big = g_malloc(len + 1);
            memset(big, ' ', len);
            memcpy(big, head, sizeof head - 1);
            big[len - 1] = ']';
            big[len] = '\0';
            g_output_stream_write_all(g_io_stream_get_output_stream(G_IO_STREAM(conn)), big, len,
                                      NULL, NULL, NULL);
            g_free(big);
            g_io_stream_close(G_IO_STREAM(conn), NULL, NULL);
            return TRUE;
        }
        if (!strcmp(buf, "j/workspaces"))
            reply = "[{\"id\":1,\"windows\":2},{\"id\":3,\"windows\":0},{\"id\":7,\"windows\":1}]";
        else if (!strcmp(buf, "j/activeworkspace"))
            reply = "{\"id\":3,\"name\":\"3\"}";
        else if (g_str_has_prefix(buf, "dispatch ")) {
            g_mutex_lock(&lock);
            g_strlcpy(last_dispatch, buf, sizeof last_dispatch);
            g_mutex_unlock(&lock);
            reply = "ok";
        }
    }
    g_output_stream_write_all(g_io_stream_get_output_stream(G_IO_STREAM(conn)), reply,
                              strlen(reply), NULL, NULL, NULL);
    g_io_stream_close(G_IO_STREAM(conn), NULL, NULL);
    return TRUE;
}

static gboolean on_events(GSocketService *svc, GSocketConnection *conn, GObject *src, gpointer d)
{
    (void)svc, (void)src, (void)d;
    g_set_object(&event_peer, conn);
    n_events_conn++;
    snap_at_conn = n_snap;
    return TRUE;
}

static void send_event(const char *lines)
{
    g_output_stream_write_all(g_io_stream_get_output_stream(G_IO_STREAM(event_peer)), lines,
                              strlen(lines), NULL, NULL, NULL);
}

static GSocketService *listen_on(GSocketService *svc, const char *path)
{
    GSocketAddress *addr = g_unix_socket_address_new(path);
    GError *err = NULL;
    if (!g_socket_listener_add_address(G_SOCKET_LISTENER(svc), addr, G_SOCKET_TYPE_STREAM,
                                       G_SOCKET_PROTOCOL_DEFAULT, NULL, NULL, &err)) {
        fprintf(stderr, "listen %s: %s\n", path, err->message);
        exit(2);
    }
    g_object_unref(addr);
    g_socket_service_start(svc);
    return svc;
}

static gboolean dispatch_seen(void)
{
    g_mutex_lock(&lock);
    gboolean seen = last_dispatch[0] != '\0';
    g_mutex_unlock(&lock);
    return seen;
}

int main(void)
{
    char *run = g_dir_make_tmp("hypr-test-XXXXXX", NULL);
    char *dir = g_build_filename(run, "hypr", "sig", NULL);
    g_mkdir_with_parents(dir, 0700);
    g_setenv("XDG_RUNTIME_DIR", run, TRUE);
    g_setenv("HYPRLAND_INSTANCE_SIGNATURE", "sig", TRUE);

    HyprCallbacks cb = {on_active, on_snapshot, on_disconnected, NULL};
    HyprClient *c = hypr_client_new(&cb);

    /* No sockets yet. */
    SPIN(n_disc >= 1, 1000);
    CHECK(n_disc >= 1, "no Hyprland is reported as disconnected");
    CHECK(n_snap == 0, "and no snapshot is taken");

    char *cmd_path = g_build_filename(dir, ".socket.sock", NULL);
    char *ev_path = g_build_filename(dir, ".socket2.sock", NULL);
    GSocketService *cmd = listen_on(g_threaded_socket_service_new(4), cmd_path);
    g_signal_connect(cmd, "run", G_CALLBACK(on_command), NULL);
    GSocketService *ev = listen_on(g_socket_service_new(), ev_path);
    g_signal_connect(ev, "incoming", G_CALLBACK(on_events), NULL);

    /* Connects on a retry and snapshots. */
    SPIN(n_snap >= 1 && event_peer, 2000);
    CHECK(n_snap == 1, "one snapshot after connecting (got %d)", n_snap);
    CHECK(last.exists[1] && last.exists[3] && last.exists[7] && !last.exists[2], "snapshot existence");
    CHECK(last.windows[1] == 2 && last.active == 3, "snapshot windows and active");

    /* An active event needs no query. */
    send_event("workspacev2>>4,4\n");
    SPIN(n_active >= 1, 1000);
    CHECK(n_active == 1 && last_active == 4, "workspacev2 -> on_active(4)");

    /* A window event refreshes. */
    int before = n_snap;
    send_event("windowtitle>>abc\nopenwindow>>abc,4,kitty,title\n");
    SPIN(n_snap > before, 1000);
    wait_stable(&n_snap);
    CHECK(n_snap == before + 1, "openwindow -> one snapshot (got %d)", n_snap - before);

    /* A burst coalesces. */
    before = n_snap;
    send_event("closewindow>>a\nclosewindow>>b\nclosewindow>>c\n"
               "closewindow>>d\nclosewindow>>e\nclosewindow>>f\n");
    SPIN(n_snap > before, 1000);
    wait_stable(&n_snap);
    CHECK(n_snap - before >= 1 && n_snap - before <= 2, "six closewindow lines -> 1..2 snapshots (got %d)",
          n_snap - before);

    /* Dispatch goes out verbatim. */
    hypr_dispatch(c, "hl.dsp.focus({ workspace = 2 })");
    SPIN(dispatch_seen(), 1000);
    CHECK(!strcmp(last_dispatch, "dispatch hl.dsp.focus({ workspace = 2 })"), "dispatch request: %s",
          last_dispatch);

    /* Losing socket2 reconnects and re-snapshots. */
    int disc = n_disc;
    before = n_snap;
    g_io_stream_close(G_IO_STREAM(event_peer), NULL, NULL);
    g_clear_object(&event_peer);
    SPIN(n_disc > disc && event_peer && n_snap > before, 2000);
    CHECK(n_disc > disc, "a closed event socket is reported");
    CHECK(event_peer != NULL, "and reconnected");
    CHECK(n_snap > before, "with a fresh snapshot");

    /* A snapshot answered before a switch must not overwrite the newer active. */
    gate_set("j/activeworkspace", FALSE);
    before = n_snap;
    int actives = n_active;
    send_event("openwindow>>s,1,kitty,t\n");
    SPIN(gate_was_hit(), 2000);
    CHECK(gate_was_hit(), "the snapshot reached j/activeworkspace");
    send_event("workspacev2>>5,5\n");
    SPIN(n_active > actives, 1000);
    gate_release();
    SPIN(n_snap > before, 2000);
    CHECK(n_snap > before && last.active == 5, "snapshot delivered after a switch keeps active 5 (got %d)",
          last.active);
    wait_stable(&n_snap);
    gate_set(NULL, TRUE);

    /* A snapshot in flight when the event socket drops is never delivered. */
    gate_set("j/workspaces", FALSE);
    send_event("openwindow>>g,1,kitty,t\n");
    SPIN(gate_was_hit(), 2000);
    CHECK(gate_was_hit(), "the snapshot is held at j/workspaces");
    before = n_snap;
    disc = n_disc;
    int conns = n_events_conn;
    g_io_stream_close(G_IO_STREAM(event_peer), NULL, NULL);
    g_clear_object(&event_peer);
    SPIN(n_disc > disc, 2000);
    CHECK(n_disc > disc, "the drop is reported while the snapshot is held");
    gate_release();
    SPIN(n_events_conn > conns, 2000);
    CHECK(n_events_conn > conns, "and the client reconnects");
    CHECK(snap_at_conn == before, "no snapshot arrived before the reconnect (%d vs %d)",
          snap_at_conn, before);
    SPIN(n_snap > before, 2000);
    CHECK(n_snap > before, "the next snapshot follows the new connection");
    wait_stable(&n_snap);
    gate_set(NULL, TRUE);

    /* A reply beyond HYPR_REPLY_MAX is dropped; the next snapshot still works. */
    wait_stable(&n_snap);
    before = n_snap;
    g_atomic_int_set(&big_reply, TRUE);
    send_event("openwindow>>b,1,kitty,t\n");
    SPIN(n_snap > before, 700);
    CHECK(n_snap == before, "an oversized j/workspaces reply yields no snapshot");
    g_atomic_int_set(&big_reply, FALSE);
    send_event("openwindow>>b2,1,kitty,t\n");
    SPIN(n_snap > before, 2000);
    CHECK(n_snap > before, "a normal snapshot works afterwards");
    wait_stable(&n_snap);

    /* An event line of 100 KiB without a newline loses the connection. */
    disc = n_disc;
    conns = n_events_conn;
    before = n_snap;
    {
        char piece[4096];
        memset(piece, 'a', sizeof piece - 1);
        piece[sizeof piece - 1] = '\0';
        for (int i = 0; i < 25 && n_disc == disc; i++) {
            send_event(piece);
            SPIN(FALSE, 5);
        }
    }
    SPIN(n_disc > disc && n_events_conn > conns, 3000);
    CHECK(n_disc > disc, "an unterminated 100 KiB event line is reported lost");
    CHECK(n_events_conn > conns, "and the client reconnects");
    SPIN(n_snap > before, 2000);
    CHECK(n_snap > before, "with a fresh snapshot");
    wait_stable(&n_snap);

    /* Free with a command query in flight: nothing is delivered afterwards. */
    gate_set("j/workspaces", FALSE);
    send_event("openwindow>>z,1,kitty,t\n");
    SPIN(gate_was_hit(), 2000);
    CHECK(gate_was_hit(), "the server received j/workspaces");
    int snaps = n_snap, acts = n_active, discs = n_disc;
    hypr_client_free(c);
    gate_release();
    SPIN(hypr_live_clients() == 0, 2000);
    CHECK(hypr_live_clients() == 0, "the freed client is released (%d live)", hypr_live_clients());
    SPIN(FALSE, 300);
    CHECK(n_snap == snaps && n_active == acts && n_disc == discs,
          "no callback after free (snap %d/%d active %d/%d disc %d/%d)", n_snap, snaps, n_active, acts,
          n_disc, discs);
    gate_set(NULL, TRUE);

    /* Freeing from inside on_disconnected must not leave the retry armed. */
    HyprCallbacks cb2 = {on_active, on_snapshot, on_disconnected_free, NULL};
    g_clear_object(&event_peer);
    c2 = hypr_client_new(&cb2);
    SPIN(event_peer != NULL, 2000);
    CHECK(event_peer != NULL, "second client connects");
    free_in_disc = TRUE;
    g_io_stream_close(G_IO_STREAM(event_peer), NULL, NULL);
    SPIN(c2 == NULL, 2000);
    CHECK(c2 == NULL, "client freed from on_disconnected");
    SPIN(hypr_live_clients() == 0, 2000);
    CHECK(hypr_live_clients() == 0, "and released (%d live)", hypr_live_clients());
    SPIN(FALSE, 6 * HYPR_RETRY_MS);

    g_socket_service_stop(cmd);
    g_socket_service_stop(ev);
    g_socket_listener_close(G_SOCKET_LISTENER(cmd));
    g_socket_listener_close(G_SOCKET_LISTENER(ev));
    g_clear_object(&event_peer);
    g_object_unref(cmd);
    g_object_unref(ev);
    g_unlink(cmd_path);
    g_unlink(ev_path);
    g_rmdir(dir);
    char *hypr_dir = g_path_get_dirname(dir);
    g_rmdir(hypr_dir);
    g_rmdir(run);
    g_free(hypr_dir);
    g_free(cmd_path);
    g_free(ev_path);
    g_free(dir);
    g_free(run);
    return check_done("test_hypr");
}
