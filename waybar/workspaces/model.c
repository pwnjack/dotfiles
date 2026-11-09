#include "model.h"

#include <errno.h>
#include <json-glib/json-glib.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

/* The range check happens on the 64-bit value, before any narrowing. */
static int slot_of(gint64 id)
{
    return id >= 1 && id <= WS_COUNT ? (int)id : 0;
}

int ws_slot(long id)
{
    return slot_of(id);
}

void ws_state_init(WsState *s)
{
    memset(s, 0, sizeof *s);
}

bool ws_visible(const WsState *s, int slot)
{
    if (slot < 1 || slot > WS_COUNT)
        return false;
    return slot <= WS_ALWAYS || s->exists[slot];
}

int ws_step(const WsState *s, int dir)
{
    if (dir == 0)
        return 0;
    dir = dir < 0 ? -1 : 1;
    int from = s->active >= 1 && s->active <= WS_COUNT ? s->active : (dir > 0 ? 0 : WS_COUNT + 1);
    for (int i = from + dir; i >= 1 && i <= WS_COUNT; i += dir)
        if (ws_visible(s, i))
            return i;
    return 0;
}

/* The root of a JSON document, owned by the caller; NULL when invalid. */
static JsonNode *parse_json(const char *json)
{
    if (!json)
        return NULL;
    JsonParser *parser = json_parser_new();
    JsonNode *root = NULL;
    if (json_parser_load_from_data(parser, json, -1, NULL))
        root = json_parser_steal_root(parser);
    g_object_unref(parser);
    return root;
}

/* An integer member, or false when absent or not an integer. */
static bool int_member(JsonObject *o, const char *name, gint64 *out)
{
    JsonNode *n = json_object_get_member(o, name);
    if (!n || !JSON_NODE_HOLDS_VALUE(n) || json_node_get_value_type(n) != G_TYPE_INT64)
        return false;
    *out = json_node_get_int(n);
    return true;
}

/* A workspace object's id. Hyprland 0.57 gives only a numbered workspace an
 * integer id; a named or special one has a string address and no id, which
 * reads as 0 (no slot). Neither, or an id of another type, is false. */
static bool id_member(JsonObject *o, gint64 *out)
{
    if (json_object_has_member(o, "id"))
        return int_member(o, "id", out);
    JsonNode *a = json_object_get_member(o, "address");
    if (!a || !JSON_NODE_HOLDS_VALUE(a) || json_node_get_value_type(a) != G_TYPE_STRING)
        return false;
    *out = 0;
    return true;
}

bool ws_parse_workspaces(const char *json, WsState *s)
{
    JsonNode *root = parse_json(json);
    if (!root || !JSON_NODE_HOLDS_ARRAY(root)) {
        if (root)
            json_node_unref(root);
        return false;
    }

    WsState next = *s;
    memset(next.exists, 0, sizeof next.exists);
    memset(next.windows, 0, sizeof next.windows);

    JsonArray *items = json_node_get_array(root);
    bool ok = true;
    for (guint i = 0; i < json_array_get_length(items); i++) {
        JsonNode *item = json_array_get_element(items, i);
        gint64 id, windows = 0;
        if (!JSON_NODE_HOLDS_OBJECT(item) || !id_member(json_node_get_object(item), &id)) {
            ok = false;
            break;
        }
        int slot = slot_of(id);
        if (!slot)
            continue;
        int_member(json_node_get_object(item), "windows", &windows);
        next.exists[slot] = true;
        next.windows[slot] = windows < 0 ? 0 : windows > INT_MAX ? INT_MAX : (int)windows;
    }
    json_node_unref(root);
    if (ok)
        *s = next;
    return ok;
}

bool ws_parse_active(const char *json, int *active)
{
    JsonNode *root = parse_json(json);
    gint64 id;
    bool ok = root && JSON_NODE_HOLDS_OBJECT(root) && id_member(json_node_get_object(root), &id);
    if (ok)
        *active = slot_of(id);
    if (root)
        json_node_unref(root);
    return ok;
}

/* A whole decimal integer in [start, end): an optional '-' then digits only,
 * so a leading space or '+' (which strtol would accept) is rejected. */
static bool parse_long(const char *start, const char *end, long *out)
{
    if (start >= end)
        return false;
    char buf[32];
    size_t n = (size_t)(end - start);
    if (n >= sizeof buf)
        return false;
    memcpy(buf, start, n);
    buf[n] = '\0';
    const char *digits = buf[0] == '-' ? buf + 1 : buf;
    if (*digits < '0' || *digits > '9')
        return false;
    char *stop;
    errno = 0;
    long v = strtol(buf, &stop, 10);
    if (errno || *stop || stop == buf)
        return false;
    *out = v;
    return true;
}

/* The slot of a workspace address in [start, end). Hyprland 0.57 addresses a
 * numbered workspace by its number and a named or special one by a name that
 * is never a number, so anything else has no slot. False when empty. */
static bool address_slot(const char *start, const char *end, int *slot)
{
    if (start >= end)
        return false;
    long id;
    *slot = parse_long(start, end, &id) ? ws_slot(id) : 0;
    return true;
}

WsEvent ws_parse_event(const char *line, int *active)
{
    const char *sep = strstr(line, ">>");
    if (!sep)
        return WS_EVENT_NONE;
    size_t len = (size_t)(sep - line);
    const char *data = sep + 2;
#define IS(name) (len == sizeof(name) - 1 && strncmp(line, name, len) == 0)

    if (IS("workspacev2")) { /* ADDRESS,NAME */
        const char *comma = strchr(data, ',');
        /* Either half may hold a comma, so a second one makes the split a
         * guess: the snapshot's j/activeworkspace answers it exactly. */
        if (comma && strchr(comma + 1, ','))
            return WS_EVENT_REFRESH;
        if (!comma || !address_slot(data, comma, active))
            return WS_EVENT_NONE;
        return WS_EVENT_ACTIVE;
    }
    if (IS("focusedmonv2")) { /* MONNAME,ADDRESS; a monitor name has no comma */
        const char *comma = strchr(data, ',');
        if (!comma || !address_slot(comma + 1, comma + 1 + strlen(comma + 1), active))
            return WS_EVENT_NONE;
        return WS_EVENT_ACTIVE;
    }
    if (IS("createworkspacev2") || IS("destroyworkspacev2") || IS("openwindow") ||
        IS("closewindow") || IS("movewindowv2"))
        return WS_EVENT_REFRESH;
    return WS_EVENT_NONE;
#undef IS
}
