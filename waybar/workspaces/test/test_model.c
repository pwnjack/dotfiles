#include <limits.h>
#include <string.h>

#include "check.h"
#include "../model.h"

static void test_workspaces(void)
{
    WsState s;
    ws_state_init(&s);
    s.active = 3;
    CHECK(ws_parse_workspaces(
              "[{\"id\":1,\"windows\":2},{\"id\":3,\"windows\":0},"
              "{\"id\":7,\"windows\":1},{\"id\":-98,\"windows\":1},{\"id\":12,\"windows\":4}]",
              &s),
          "valid workspaces parse");
    CHECK(s.exists[1] && s.windows[1] == 2, "slot 1 exists with 2 windows");
    CHECK(s.exists[3] && s.windows[3] == 0, "slot 3 exists, empty");
    CHECK(s.exists[7] && s.windows[7] == 1, "slot 7 exists");
    CHECK(!s.exists[2] && !s.exists[10], "absent slots stay absent");
    CHECK(s.active == 3, "active is kept");

    WsState before = s;
    CHECK(!ws_parse_workspaces("not json", &s), "garbage is rejected");
    CHECK(!ws_parse_workspaces("{\"id\":1}", &s), "an object is rejected");
    CHECK(!ws_parse_workspaces("[{\"windows\":1}]", &s), "an element without id or address is rejected");
    CHECK(!ws_parse_workspaces("[{\"id\":\"1\"}]", &s), "a string id is rejected");
    CHECK(!ws_parse_workspaces("[{\"id\":2,\"windows\":1},{\"id\":null,\"address\":\"x\"}]", &s),
          "a null id is rejected, address or not");
    CHECK(!ws_parse_workspaces("[{\"address\":7}]", &s), "a non-string address is rejected");
    CHECK(!ws_parse_workspaces("[{\"id\":2,\"windows\":1},3]", &s), "a non-object element is rejected");
    CHECK(!ws_parse_workspaces(NULL, &s), "NULL is rejected");
    CHECK(memcmp(&before, &s, sizeof s) == 0, "a rejected parse leaves the state untouched");

    WsState w;
    ws_state_init(&w);
    CHECK(ws_parse_workspaces("[{\"id\":2,\"windows\":-5},{\"id\":3,\"windows\":9999999999}]", &w),
          "out-of-range window counts parse");
    CHECK(w.windows[2] == 0, "a negative window count clamps to 0");
    CHECK(w.windows[3] == INT_MAX, "a huge window count clamps to INT_MAX");
    ws_state_init(&w);
    CHECK(ws_parse_workspaces("[{\"id\":4294967297,\"windows\":1}]", &w) && !w.exists[1],
          "an id that wraps to 1 in 32 bits has no slot");

    ws_state_init(&w);
    CHECK(ws_parse_workspaces("[{\"id\":2,\"windows\":1},"
                              "{\"address\":\"special:x\",\"type\":\"special\",\"windows\":1},"
                              "{\"address\":\"B\",\"type\":\"normal\",\"windows\":3}]",
                              &w),
          "named and special workspaces (Hyprland 0.57: address, no id) do not reject the list");
    CHECK(w.exists[2] && w.windows[2] == 1, "the numbered workspace parses beside them");
    CHECK(!w.exists[3] && !w.exists[1], "a named or special workspace takes no slot");

    CHECK(ws_parse_workspaces("[]", &s), "an empty list parses");
    CHECK(!s.exists[1] && !s.exists[7], "an empty list clears every slot");
}

static void test_active(void)
{
    int a = -1;
    CHECK(ws_parse_active("{\"id\":4,\"name\":\"4\"}", &a) && a == 4, "active 4");
    CHECK(ws_parse_active("{\"id\":-98}", &a) && a == 0, "a special workspace has no slot");
    CHECK(ws_parse_active("{\"id\":11}", &a) && a == 0, "workspace 11 has no slot");
    a = 5;
    CHECK(!ws_parse_active("[]", &a) && a == 5, "a non-object is rejected, active untouched");
    CHECK(!ws_parse_active("{}", &a) && a == 5, "a missing id and address is rejected");
    CHECK(!ws_parse_active("{\"id\":null}", &a) && a == 5, "a null id is rejected");
    CHECK(ws_parse_active("{\"address\":\"B\",\"type\":\"normal\",\"name\":\"B\"}", &a) && a == 0,
          "a named workspace (Hyprland 0.57: address, no id) has no slot");
}

static void test_events(void)
{
    int a = -1;
    CHECK(ws_parse_event("workspacev2>>4,4", &a) == WS_EVENT_ACTIVE && a == 4, "workspacev2");
    CHECK(ws_parse_event("workspacev2>>-98,special:magic", &a) == WS_EVENT_ACTIVE && a == 0,
          "a negative workspace id has no slot");
    CHECK(ws_parse_event("focusedmonv2>>DP-1,3", &a) == WS_EVENT_ACTIVE && a == 3, "focusedmonv2");
    /* Hyprland 0.57 addresses a named workspace by its bare name, never a
     * number: anything not a whole number is outside the row, not a slot. */
    a = 7;
    CHECK(ws_parse_event("workspacev2>>B,B", &a) == WS_EVENT_ACTIVE && a == 0, "a named workspace has no slot");
    a = 7;
    CHECK(ws_parse_event("focusedmonv2>>DP-1,B", &a) == WS_EVENT_ACTIVE && a == 0,
          "focusedmonv2 to a named workspace has no slot");
    a = 7;
    CHECK(ws_parse_event("focusedmonv2>>DP-1,x,4", &a) == WS_EVENT_ACTIVE && a == 0,
          "a comma in the address stays in the address");
    a = 7;
    CHECK(ws_parse_event("workspacev2>>4,x,4,x", &a) == WS_EVENT_REFRESH && a == 7,
          "an ambiguous comma (named 4,x) refreshes instead of guessing slot 4");
    a = 7;
    CHECK(ws_parse_event("workspacev2>>x4,4", &a) == WS_EVENT_ACTIVE && a == 0, "x4 is a name, not slot 4");
    a = 7;
    CHECK(ws_parse_event("workspacev2>> 4,4", &a) == WS_EVENT_ACTIVE && a == 0, "a leading space is not slot 4");
    a = 7;
    CHECK(ws_parse_event("workspacev2>>+4,4", &a) == WS_EVENT_ACTIVE && a == 0, "a leading plus is not slot 4");
    a = 7;
    CHECK(ws_parse_event("workspacev2>>", &a) == WS_EVENT_NONE && a == 7, "an empty payload is ignored");
    CHECK(ws_parse_event("workspacev2>>,4", &a) == WS_EVENT_NONE && a == 7, "an empty address is ignored");
    CHECK(ws_parse_event("focusedmonv2>>DP-1,", &a) == WS_EVENT_NONE && a == 7,
          "an empty focusedmonv2 address is ignored");
    CHECK(ws_parse_event("focusedmonv2>>DP-1", &a) == WS_EVENT_NONE && a == 7, "a missing comma is ignored");
    CHECK(ws_parse_event("createworkspacev2>>6,6", &a) == WS_EVENT_REFRESH, "createworkspacev2");
    CHECK(ws_parse_event("destroyworkspacev2>>6,6", &a) == WS_EVENT_REFRESH, "destroyworkspacev2");
    CHECK(ws_parse_event("openwindow>>55b9,1,kitty,Kitty", &a) == WS_EVENT_REFRESH, "openwindow");
    CHECK(ws_parse_event("closewindow>>55b9", &a) == WS_EVENT_REFRESH, "closewindow");
    CHECK(ws_parse_event("movewindowv2>>55b9,4,4", &a) == WS_EVENT_REFRESH, "movewindowv2");
    CHECK(ws_parse_event("windowtitle>>55b9", &a) == WS_EVENT_NONE, "windowtitle is ignored");
    CHECK(ws_parse_event("workspace>>4", &a) == WS_EVENT_NONE, "the v1 event is ignored (v2 is used)");
    CHECK(ws_parse_event("no separator", &a) == WS_EVENT_NONE, "a line without >> is ignored");
}

static void test_visible(void)
{
    WsState s;
    ws_state_init(&s);
    CHECK(ws_visible(&s, 1) && ws_visible(&s, 5), "1-5 are always visible");
    CHECK(!ws_visible(&s, 6) && !ws_visible(&s, 10), "6-10 are hidden until they exist");
    s.exists[8] = true;
    CHECK(ws_visible(&s, 8), "an existing optional slot is visible");
    CHECK(!ws_visible(&s, 0) && !ws_visible(&s, 11), "out-of-range slots are never visible");
    CHECK(ws_slot(1) == 1 && ws_slot(10) == 10 && ws_slot(0) == 0 && ws_slot(11) == 0 && ws_slot(-3) == 0,
          "ws_slot bounds");
}

static void test_step(void)
{
    WsState s;
    ws_state_init(&s);
    s.active = 1;
    CHECK(ws_step(&s, 1) == 2, "down from 1 goes to 2");
    CHECK(ws_step(&s, -1) == 0, "up from 1 stops at the first slot");
    s.active = 5;
    CHECK(ws_step(&s, 1) == 0, "down from 5 stops when 6-10 do not exist");
    CHECK(ws_step(&s, -1) == 4, "up from 5 goes to 4");
    s.exists[8] = true;
    CHECK(ws_step(&s, 1) == 8, "down from 5 skips the hidden 6 and 7");
    s.active = 8;
    CHECK(ws_step(&s, -1) == 5, "up from 8 skips back over 6 and 7");
    CHECK(ws_step(&s, 1) == 0, "down from the last visible slot stops");
    s.exists[10] = true;
    s.active = 10;
    CHECK(ws_step(&s, 1) == 0, "down from 10 never leaves the row");
    s.active = 0;
    CHECK(ws_step(&s, 1) == 1, "outside the row, down enters at the first slot");
    CHECK(ws_step(&s, -1) == 10, "outside the row, up enters at the last visible slot");
    s.exists[10] = false;
    CHECK(ws_step(&s, -1) == 8, "outside the row, up skips hidden slots");
    s.active = 3;
    CHECK(ws_step(&s, 0) == 0, "no direction, no step");
}

int main(void)
{
    test_workspaces();
    test_active();
    test_events();
    test_visible();
    test_step();
    return check_done("test_model");
}
