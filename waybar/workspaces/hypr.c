#include "hypr.h"

#include <gio/gio.h>
#include <gio/gunixsocketaddress.h>
#include <string.h>

#ifndef HYPR_RETRY_MS
#define HYPR_RETRY_MS 2000
#endif

#define HYPR_REPLY_MAX (1024 * 1024) /* a command reply larger than this fails the query */
#define HYPR_EVENT_MAX (64 * 1024)   /* an event line longer than this is a lost connection */
#define HYPR_QUERY_TIMEOUT_S 5
#define HYPR_READ_CHUNK 16384

struct HyprClient {
    int refs;      /* every pending async operation holds one */
    gboolean dead; /* hypr_client_free ran: no more callbacks */
    HyprCallbacks cb;
    GCancellable *cancel;
    GSocketClient *sockets; /* the event socket: no timeout, it idles */
    GSocketClient *queries; /* command sockets: a stalled peer times out */
    GSocketConnection *events;
    GInputStream *events_in; /* borrowed from `events` */
    GByteArray *acc;         /* bytes read from the event socket, no full line yet */
    guint retry_id;
    gboolean snapshot_busy, snapshot_again;
    gboolean has_pending_active; /* an active event arrived while a snapshot was in flight */
    int pending_active;
    unsigned generation; /* bumped on every disconnect; a snapshot belongs to one */
};

#ifdef HYPR_TEST
static int live_clients;
int hypr_live_clients(void) { return live_clients; }
#endif

static HyprClient *ref(HyprClient *c)
{
    c->refs++;
    return c;
}

static void unref(HyprClient *c)
{
    if (--c->refs > 0)
        return;
    g_clear_object(&c->events);
    g_clear_object(&c->sockets);
    g_clear_object(&c->queries);
    g_clear_object(&c->cancel);
    if (c->acc)
        g_byte_array_free(c->acc, TRUE);
    g_free(c);
#ifdef HYPR_TEST
    live_clients--;
#endif
}

static char *socket_path(const char *name)
{
    const char *run = g_getenv("XDG_RUNTIME_DIR");
    const char *sig = g_getenv("HYPRLAND_INSTANCE_SIGNATURE");
    if (!run || !*run || !sig || !*sig)
        return NULL;
    return g_build_filename(run, "hypr", sig, name, NULL);
}

/* ---- one request on the command socket -------------------------------- */

/* reply: owned by the callee, NULL on failure. Always called, even after
 * free; implementations check c->dead before touching the owner. */
typedef void (*QueryDone)(HyprClient *c, char *reply, gpointer data);

typedef struct {
    HyprClient *c;
    char *request;
    QueryDone done;
    gpointer data;
    GSocketConnection *conn;
    GByteArray *acc;
} Query;

static void query_finish(Query *q, char *reply)
{
    q->done(q->c, reply, q->data);
    g_clear_object(&q->conn);
    if (q->acc)
        g_byte_array_free(q->acc, TRUE);
    g_free(q->request);
    unref(q->c);
    g_free(q);
}

static void query_read(Query *q);

static void query_read_done(GObject *src, GAsyncResult *res, gpointer user)
{
    Query *q = user;
    GBytes *chunk = g_input_stream_read_bytes_finish(G_INPUT_STREAM(src), res, NULL);
    if (!chunk) {
        query_finish(q, NULL);
        return;
    }
    gsize n = g_bytes_get_size(chunk);
    if (n == 0) { /* EOF: the reply is complete */
        g_bytes_unref(chunk);
        g_byte_array_append(q->acc, (const guint8 *)"", 1);
        char *reply = (char *)g_byte_array_free(q->acc, FALSE);
        q->acc = NULL;
        query_finish(q, reply);
        return;
    }
    if (q->acc->len + n > HYPR_REPLY_MAX) {
        g_bytes_unref(chunk);
        g_printerr("workspaces: reply to '%s' exceeds %d bytes; dropped\n", q->request,
                   HYPR_REPLY_MAX);
        query_finish(q, NULL);
        return;
    }
    g_byte_array_append(q->acc, g_bytes_get_data(chunk, NULL), n);
    g_bytes_unref(chunk);
    query_read(q);
}

static void query_read(Query *q)
{
    g_input_stream_read_bytes_async(g_io_stream_get_input_stream(G_IO_STREAM(q->conn)),
                                    HYPR_READ_CHUNK, G_PRIORITY_DEFAULT, q->c->cancel,
                                    query_read_done, q);
}

static gboolean query_fail_idle(gpointer user)
{
    query_finish(user, NULL);
    return G_SOURCE_REMOVE;
}

/* Connect and write the request in one synchronous step, as hyprctl does; only
 * the reply is read asynchronously. Hyprland reads a command on its main
 * thread, blocking (up to 5 s) from accept() until the request arrives. An
 * async connect wrote it on a later main-loop iteration, and when Waybar's own
 * Hyprland modules made a synchronous call in between, Waybar and Hyprland
 * waited on each other: a 5 s compositor freeze on every window close. A local
 * connect and a request this small do not block. */
static void query(HyprClient *c, const char *request, QueryDone done, gpointer data)
{
    Query *q = g_new0(Query, 1);
    q->c = ref(c);
    q->request = g_strdup(request);
    q->done = done;
    q->data = data;
    char *path = socket_path(".socket.sock");
    if (!path) { /* report asynchronously: no callback runs in the caller's stack */
        g_idle_add(query_fail_idle, q);
        return;
    }
    GSocketAddress *addr = g_unix_socket_address_new(path);
    g_free(path);
    q->conn = g_socket_client_connect(c->queries, G_SOCKET_CONNECTABLE(addr), c->cancel, NULL);
    g_object_unref(addr);
    if (!q->conn ||
        !g_output_stream_write_all(g_io_stream_get_output_stream(G_IO_STREAM(q->conn)), q->request,
                                   strlen(q->request), NULL, c->cancel, NULL)) {
        g_idle_add(query_fail_idle, q);
        return;
    }
    q->acc = g_byte_array_new();
    query_read(q);
}

/* ---- coalesced snapshots ---------------------------------------------- */

typedef struct {
    WsState st;
    unsigned generation; /* the event connection this snapshot started in */
} Snap;

static void snapshot_start(HyprClient *c);

static void snapshot_end(HyprClient *c)
{
    c->snapshot_busy = FALSE;
    if (c->snapshot_again && !c->dead) {
        c->snapshot_again = FALSE;
        snapshot_start(c);
    }
}

static void snapshot_active_done(HyprClient *c, char *reply, gpointer data)
{
    Snap *snap = data;
    WsState *st = &snap->st;
    /* A snapshot of a connection already reported lost is never delivered. */
    if (!c->dead && snap->generation == c->generation) {
        if (reply && ws_parse_active(reply, &st->active)) {
            /* An active event that arrived while this snapshot was in flight is
             * newer than the reply, however the two raced. */
            if (c->has_pending_active)
                st->active = c->pending_active;
            c->has_pending_active = FALSE;
            /* The consumer may free the client here; nothing below touches
             * the owner, and the query still holds a reference. */
            c->cb.on_snapshot(st, c->cb.data);
        } else
            g_printerr("workspaces: j/activeworkspace failed; keeping the last state\n");
    }
    g_free(reply);
    g_free(snap);
    snapshot_end(c);
}

static void snapshot_workspaces_done(HyprClient *c, char *reply, gpointer data)
{
    Snap *snap = data;
    if (c->dead || !reply || !ws_parse_workspaces(reply, &snap->st)) {
        if (!c->dead)
            g_printerr("workspaces: j/workspaces failed; keeping the last state\n");
        g_free(reply);
        g_free(snap);
        snapshot_end(c);
        return;
    }
    g_free(reply);
    query(c, "j/activeworkspace", snapshot_active_done, snap);
}

static void snapshot_start(HyprClient *c)
{
    if (c->snapshot_busy) {
        c->snapshot_again = TRUE;
        return;
    }
    c->snapshot_busy = TRUE;
    c->has_pending_active = FALSE;
    Snap *snap = g_new0(Snap, 1);
    snap->generation = c->generation;
    ws_state_init(&snap->st);
    query(c, "j/workspaces", snapshot_workspaces_done, snap);
}

/* ---- the event socket ------------------------------------------------- */

static void events_connect(HyprClient *c);
static void events_read_done(GObject *src, GAsyncResult *res, gpointer user);

static gboolean retry_fire(gpointer user)
{
    HyprClient *c = user;
    c->retry_id = 0;
    if (!c->dead)
        events_connect(c);
    return G_SOURCE_REMOVE;
}

static void retry_release(gpointer user)
{
    unref(user);
}

/* Callers hold a reference across this call. */
static void disconnected(HyprClient *c)
{
    c->generation++;
    c->events_in = NULL;
    g_clear_object(&c->events);
    if (c->acc)
        g_byte_array_set_size(c->acc, 0);
    if (c->dead)
        return;
    if (c->cb.on_disconnected) {
        c->cb.on_disconnected(c->cb.data);
        if (c->dead) /* the consumer freed the client from its callback */
            return;
    }
    if (!c->retry_id)
        c->retry_id = g_timeout_add_full(G_PRIORITY_DEFAULT, HYPR_RETRY_MS, retry_fire, ref(c),
                                         retry_release);
}

static void events_read(HyprClient *c)
{
    g_input_stream_read_bytes_async(c->events_in, 4096, G_PRIORITY_DEFAULT, c->cancel,
                                    events_read_done, c);
}

/* Handles one complete line; FALSE when the consumer freed the client. */
static gboolean event_line(HyprClient *c, const char *line)
{
    int active = 0;
    switch (ws_parse_event(line, &active)) {
    case WS_EVENT_ACTIVE:
        if (c->snapshot_busy) {
            c->has_pending_active = TRUE;
            c->pending_active = active;
        }
        c->cb.on_active(active, c->cb.data);
        return !c->dead;
    case WS_EVENT_REFRESH:
        snapshot_start(c);
        break;
    case WS_EVENT_NONE:
        break;
    }
    return TRUE;
}

static void events_read_done(GObject *src, GAsyncResult *res, gpointer user)
{
    HyprClient *c = user;
    GBytes *chunk = g_input_stream_read_bytes_finish(G_INPUT_STREAM(src), res, NULL);
    if (c->dead) {
        if (chunk)
            g_bytes_unref(chunk);
        unref(c);
        return;
    }
    gsize n = chunk ? g_bytes_get_size(chunk) : 0;
    if (n == 0) { /* EOF or error: Hyprland went away */
        if (chunk)
            g_bytes_unref(chunk);
        disconnected(c);
        unref(c);
        return;
    }
    g_byte_array_append(c->acc, g_bytes_get_data(chunk, NULL), n);
    g_bytes_unref(chunk);

    guint8 *nl;
    while ((nl = memchr(c->acc->data, '\n', c->acc->len))) {
        guint len = nl - c->acc->data;
        char *line = g_strndup((const char *)c->acc->data, len);
        g_byte_array_remove_range(c->acc, 0, len + 1);
        gboolean alive = event_line(c, line);
        g_free(line);
        if (!alive) {
            unref(c);
            return;
        }
    }
    if (c->acc->len > HYPR_EVENT_MAX) {
        g_printerr("workspaces: event line exceeds %d bytes; reconnecting\n", HYPR_EVENT_MAX);
        disconnected(c);
        unref(c);
        return;
    }
    /* The pending read keeps the reference this callback was holding. */
    events_read(c);
}

static void events_connect_done(GObject *src, GAsyncResult *res, gpointer user)
{
    HyprClient *c = user;
    GSocketConnection *conn = g_socket_client_connect_finish(G_SOCKET_CLIENT(src), res, NULL);
    if (c->dead) {
        if (conn)
            g_object_unref(conn);
        unref(c);
        return;
    }
    if (!conn) {
        disconnected(c);
        unref(c);
        return;
    }
    c->events = conn;
    c->events_in = g_io_stream_get_input_stream(G_IO_STREAM(conn));
    if (!c->acc)
        c->acc = g_byte_array_new();
    snapshot_start(c);
    events_read(c);
}

static gboolean no_socket_idle(gpointer user)
{
    HyprClient *c = user;
    disconnected(c);
    unref(c);
    return G_SOURCE_REMOVE;
}

static void events_connect(HyprClient *c)
{
    char *path = socket_path(".socket2.sock");
    if (!path) { /* report asynchronously: no callback runs in the caller's stack */
        g_idle_add(no_socket_idle, ref(c));
        return;
    }
    GSocketAddress *addr = g_unix_socket_address_new(path);
    g_free(path);
    g_socket_client_connect_async(c->sockets, G_SOCKET_CONNECTABLE(addr), c->cancel,
                                  events_connect_done, ref(c));
    g_object_unref(addr);
}

/* ---- public ----------------------------------------------------------- */

static void dispatch_done(HyprClient *c, char *reply, gpointer data)
{
    (void)data;
    if (!c->dead && (!reply || strcmp(reply, "ok") != 0))
        g_printerr("workspaces: dispatch failed: %.200s\n", reply ? reply : "no reply");
    g_free(reply);
}

void hypr_dispatch(HyprClient *c, const char *lua)
{
    char *request = g_strconcat("dispatch ", lua, NULL);
    query(c, request, dispatch_done, NULL);
    g_free(request);
}

HyprClient *hypr_client_new(const HyprCallbacks *cb)
{
    HyprClient *c = g_new0(HyprClient, 1);
    c->refs = 1;
#ifdef HYPR_TEST
    live_clients++;
#endif
    c->cb = *cb;
    c->cancel = g_cancellable_new();
    c->sockets = g_socket_client_new();
    c->queries = g_socket_client_new();
    g_socket_client_set_timeout(c->queries, HYPR_QUERY_TIMEOUT_S);
    events_connect(c);
    return c;
}

void hypr_client_free(HyprClient *c)
{
    if (!c)
        return;
    c->dead = TRUE;
    if (c->retry_id) {
        g_source_remove(c->retry_id);
        c->retry_id = 0;
    }
    g_cancellable_cancel(c->cancel);
    unref(c);
}
