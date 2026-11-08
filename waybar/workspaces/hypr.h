/* Hyprland IPC for the native module. Events and replies are read
 * asynchronously on the GLib main loop; each command connects and writes
 * synchronously (see query() in hypr.c: an async write once deadlocked the
 * compositor for five seconds). The event socket (.socket2.sock) is read line
 * by line; every query opens its own command-socket (.socket.sock)
 * connection, as hyprctl does. Nothing polls: a lost or missing Hyprland is
 * retried every HYPR_RETRY_MS. */
#pragma once
#include "model.h"

typedef struct HyprClient HyprClient;

/* on_active and on_snapshot are required; on_disconnected is optional. While
 * Hyprland is absent on_disconnected repeats on every retry, so consumers must
 * be idempotent. No callback runs inside hypr_client_new or hypr_dispatch, and
 * a consumer may call hypr_client_free from any of them. on_snapshot is never
 * delivered for a connection that has already been reported lost: a snapshot
 * still in flight when the event socket drops is discarded, and the next one
 * comes only after the client reconnects. */
typedef struct {
    void (*on_active)(int active, void *data);             /* straight from an event */
    void (*on_snapshot)(const WsState *state, void *data); /* full, consistent state */
    void (*on_disconnected)(void *data);                   /* no Hyprland right now */
    void *data;
} HyprCallbacks;

HyprClient *hypr_client_new(const HyprCallbacks *cb);
/* Stops every callback at once; in-flight I/O finishes harmlessly later. */
void hypr_client_free(HyprClient *c);
/* `lua` is a dispatcher expression, e.g. "hl.dsp.focus({ workspace = 4 })". */
void hypr_dispatch(HyprClient *c, const char *lua);
#ifdef HYPR_TEST
/* Clients created and not yet fully released (tests only). */
int hypr_live_clients(void);
#endif
