/* Workspace state for the native module: which of the ten slots exist,
 * which have windows, which is active. Pure; parsing uses json-glib. */
#pragma once
#include <stdbool.h>
#include <stdint.h>

#define WS_COUNT 10  /* slots 1..10; index 0 is unused */
#define WS_ALWAYS 5  /* slots 1..5 are drawn whether or not they exist */

typedef struct {
    bool exists[WS_COUNT + 1];
    int windows[WS_COUNT + 1];
    int active; /* 1..10, or 0 when the active workspace has no slot */
} WsState;

typedef enum { WS_EVENT_NONE, WS_EVENT_ACTIVE, WS_EVENT_REFRESH } WsEvent;

/* 1..10 for a slot id, 0 for anything else (named and special workspaces
 * have no number). */
int ws_slot(int64_t id);
void ws_state_init(WsState *s);
bool ws_visible(const WsState *s, int slot);
/* The visible slot one step from the active one in direction dir (-1 or +1),
 * or 0 at either end of the row (and for dir 0): scrolling stops rather than
 * wraps. From outside the row (active 0), +1 enters at the first slot and -1
 * at the last. */
int ws_step(const WsState *s, int dir);
/* j/workspaces. Replaces exists/windows; keeps active. False: s untouched. */
bool ws_parse_workspaces(const char *json, WsState *s);
/* j/activeworkspace. False: *active untouched. */
bool ws_parse_active(const char *json, int *active);
/* One socket2 line without its newline. *active is set only for ACTIVE. */
WsEvent ws_parse_event(const char *line, int *active);
