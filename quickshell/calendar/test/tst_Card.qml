import QtQuick
import QtTest
import ".."
import "../model.mjs" as Model

Item {
    id: host
    width: 1600; height: 900
    QtObject {
        id: controller
        property color background: "#05090c"; property color foreground: "#cfddde"
        property color accent: "#6097a1"; property color accentInk: "#05090c"
        property string monoFont: "monospace"; property real uiScale: 1
        property bool barAtBottom: false
        property string clock: "24h"
        property var locale: Qt.locale("it_IT")
        property var state: Model.transition(Model.CLOSED, "clock")
        property var status: ({ state: "ok", kind: "", message: "", lastSuccess: 1000, lastAttempt: 1000 })
        property double now: 1000 + 180
        property double openedAt: 0
        property bool syncGaveUp: false
        property var agenda: []
        property var calendars: [{ name: "Home", color: "#ff9f0a", writable: true }]
        property var busy: ({}); property var counts: ({})
        property var dayEvents: []; property string dayFor: ""
        property var draft: null; property string addError: ""; property string highlight: ""
        property int viewYear: new Date().getFullYear(); property int viewMonth: new Date().getMonth()
        property string lastAction: ""
        function act(a) { lastAction = a; state = Model.transition(state, a); }
        // The same rule as the real controller (shell.qml headerStatus).
        function headerStatus() {
            if (!syncGaveUp && (!status || (status.lastAttempt || 0) < openedAt - 1)) return "syncing…";
            if (!status || status.state === "none") return "Not signed in";
            if (status.state === "failed") return status.kind === "auth" ? "Sign-in rejected · Fix in Settings"
                : "Offline · showing events from " + Model.formatTime(Model.minutesOf(status.lastSuccess), clock, "AM", "PM");
            return "iCloud · synced " + Math.round((now - status.lastSuccess) / 60) + " min ago";
        }
        function goToday() {} function newEvent() { state = Model.openSheet(state); }
        function selectDay(k) { state = Object.assign({}, state, { day: k }); }
        function showYear() { state = Object.assign({}, state, { year: true }); }
        property int lastShift: 0; property int lastMonth: -1
        property string peekFor: ""; property var peekEvents: []
        function pickMonth(m) { lastMonth = m; } function shiftMonth(d) { lastShift = d; } function shiftYear(d) { lastShift = d; }
        function loadPeek(key) { peekFor = key; }
        function toggleUpcoming() { state = Object.assign({}, state, { unfolded: !state.unfolded }); }
        function openSettings() {} function cancelSheet() {} function add() {}
    }
    Card { id: card; controller: controller; x: Math.round((host.width - width) / 2) }
    TestCase {
        name: "Card"
        when: windowShown
        function find(name) { return findChild(card, name); }
        function test_header_status() {
            compare(find("syncStatus").text, "iCloud · synced 3 min ago");
            controller.status = { state: "failed", kind: "auth", message: "Sign-in rejected", lastSuccess: 1000, lastAttempt: 1000 };
            compare(find("syncStatus").text, "Sign-in rejected · Fix in Settings");
            controller.status = { state: "none", kind: "", message: "", lastSuccess: null, lastAttempt: 1000 };
            compare(find("syncStatus").text, "Not signed in");
            verify(!find("plusButton").enabled);
            controller.status = { state: "ok", kind: "", message: "", lastSuccess: 1000, lastAttempt: 1000 };
            verify(find("plusButton").enabled);
        }
        function test_syncing_until_the_attempt_is_newer_than_open() {
            controller.openedAt = 2000;
            compare(find("syncStatus").text, "syncing…");
            controller.status = { state: "ok", kind: "", message: "", lastSuccess: 1100, lastAttempt: 2000 };
            compare(find("syncStatus").text, "iCloud · synced 1 min ago");
            controller.status = { state: "ok", kind: "", message: "", lastSuccess: 1000, lastAttempt: 1000 };
            compare(find("syncStatus").text, "syncing…");
            controller.syncGaveUp = true;
            compare(find("syncStatus").text, "iCloud · synced 3 min ago");
            controller.syncGaveUp = false;
            controller.openedAt = 0;
            controller.status = { state: "ok", kind: "", message: "", lastSuccess: 1000, lastAttempt: 1000 };
        }
        function test_give_up_with_no_status_says_not_signed_in() {
            controller.openedAt = 2000;
            controller.status = null;
            compare(find("syncStatus").text, "syncing…");
            controller.syncGaveUp = true;
            compare(find("syncStatus").text, "Not signed in");
            controller.syncGaveUp = false;
            controller.openedAt = 0;
            controller.status = { state: "ok", kind: "", message: "", lastSuccess: 1000, lastAttempt: 1000 };
        }
        function test_long_date_is_italian() {
            const expected = Qt.locale("it_IT").toString(new Date(), "dddd d MMMM yyyy");
            compare(find("longDate").text, expected);
        }
        function test_long_status_keeps_plus_inside_the_frame() {
            const month = controller.viewMonth;
            controller.status = { state: "failed", kind: "network", message: "", lastSuccess: 1000, lastAttempt: 1000 };
            controller.viewMonth = (month + 1) % 12;          // away from this month: Today shows
            waitForRendering(card);
            verify(find("todayButton").visible);
            const plus = find("plusButton");
            const right = plus.mapToItem(card, plus.width, 0).x;
            verify(right <= card.width - 16, "the + button reaches x=" + right + " on a " + card.width + " px card");
            controller.viewMonth = month;
            controller.status = { state: "ok", kind: "", message: "", lastSuccess: 1000, lastAttempt: 1000 };
            waitForRendering(card);
        }
        function test_x_is_fixed_across_views() {
            const x0 = card.x;
            controller.state = Model.transition(Model.CLOSED, "pill"); compare(card.x, x0);
            controller.state = Object.assign({}, controller.state, { day: "2026-10-13" }); compare(card.x, x0);
            controller.state = Model.openSheet(controller.state); compare(card.x, x0);
            controller.state = Model.transition(Model.CLOSED, "clock");
        }
        function test_escape_goes_through_the_controller() {
            card.forceActiveFocus();
            keyClick(Qt.Key_Escape);
            compare(controller.lastAction, "esc");
        }
        // The tests share one controller: each starts from the same clock, agenda and month data.
        function cleanup() {
            controller.now = 1000 + 180;
            controller.agenda = []; controller.busy = ({}); controller.counts = ({});
            controller.peekFor = ""; controller.peekEvents = [];
            controller.dayFor = ""; controller.dayEvents = []; controller.clock = "24h";
            controller.status = { state: "ok", kind: "", message: "", lastSuccess: 1000, lastAttempt: 1000 };
            controller.state = Model.transition(Model.CLOSED, "clock");
            card.peekEvents = []; card.peekAnchor = null; card.peekPending = "";
        }
        function rowsNamed(item, name) {
            let out = [];
            for (const c of item.children) { if (c.objectName === name) out.push(c); out = out.concat(rowsNamed(c, name)); }
            return out;
        }
        function hasText(item, text) {
            for (const c of item.children) { if (c.text === text || hasText(c, text)) return true; }
            return false;
        }
        function test_month_weekdays_start_on_monday_in_italian() {
            compare(find("weekday0").text, Qt.locale("it_IT").dayName(1, Locale.ShortFormat));
        }
        function test_busy_dots() {
            const key = controller.viewYear + "-" + String(controller.viewMonth + 1).padStart(2, "0");
            const b = {}; b[key] = [13]; controller.busy = b;
            verify(find("dot-" + key + "-13").visible);
            verify(!find("dot-" + key + "-12").visible);
        }
        function test_wheel_and_month_name() {
            const before = controller.lastAction;
            mouseClick(find("monthName"));
            verify(controller.state.year);
            controller.state = Model.transition(Model.CLOSED, "clock");
        }
        function test_folded_line() {
            const t = Math.floor(Date.now() / 1000);
            controller.now = t;
            controller.agenda = [{ title: "Dentist", calendar: "Home", color: "#ff9f0a", location: "", allDay: false,
                startEpoch: t + 3600, endEpoch: t + 7200 }];
            verify(find("foldedLine").text.indexOf("Dentist") >= 0);
            mouseClick(find("foldedLine"));
            verify(controller.state.unfolded);
            controller.state = Model.transition(Model.CLOSED, "clock");
        }
        function test_set_up_row_without_account() {
            controller.status = { state: "none", kind: "", message: "", lastSuccess: null, lastAttempt: 1 };
            verify(find("setUpRow").visible);
            controller.status = { state: "ok", kind: "", message: "", lastSuccess: 1000, lastAttempt: 1000 };
        }
        function test_day_view_new_event_button() {
            controller.state = Object.assign({}, Model.transition(Model.CLOSED, "clock"), { day: "2026-10-13" });
            controller.dayFor = "2026-10-13"; controller.dayEvents = [];
            verify(find("newOnDay").text.indexOf(Qt.locale("it_IT").toString(new Date(2026, 9, 13), "ddd d")) >= 0);
            mouseClick(find("newOnDayButton"));
            verify(controller.state.sheet);
            controller.state = Model.transition(Model.CLOSED, "clock");
        }
        function test_year_month_click_picks_that_month() {
            controller.state = Object.assign({}, Model.transition(Model.CLOSED, "clock"), { year: true });
            mouseClick(find("yearMonth3"));
            compare(controller.lastMonth, 3);
            controller.state = Model.transition(Model.CLOSED, "clock");
        }
        function test_unfolded_groups_are_headed_today_and_tomorrow() {
            const t = Math.floor(Date.now() / 1000);
            controller.now = t;
            controller.agenda = [
                { title: "Now", calendar: "Home", color: "", location: "", allDay: false, startEpoch: t + 60, endEpoch: t + 1800 },
                { title: "Later", calendar: "Home", color: "", location: "", allDay: true, startEpoch: t + 86400, endEpoch: t + 172800 },
            ];
            controller.state = Object.assign({}, Model.transition(Model.CLOSED, "clock"), { unfolded: true });
            waitForRendering(card);
            verify(hasText(card, "Today"));
            verify(hasText(card, "Tomorrow"));
            verify(hasText(card, "all day"));
            controller.agenda = [];
            controller.state = Model.transition(Model.CLOSED, "clock");
        }
        function test_long_titles_stay_inside_the_card() {
            const t = Math.floor(Date.now() / 1000);
            controller.now = t;
            controller.agenda = [{ title: "x".repeat(300), calendar: "Home", color: "", location: "", allDay: false,
                startEpoch: t + 60, endEpoch: t + 1800 }];
            controller.state = Object.assign({}, Model.transition(Model.CLOSED, "clock"), { unfolded: true });
            waitForRendering(card);
            const rows = rowsNamed(card, "eventRow");
            verify(rows.length > 0);
            for (const r of rows) {
                const right = r.mapToItem(card, r.width, 0).x;
                verify(right <= card.width, "a row reaches x=" + right + " on a " + card.width + " px card");
            }
            controller.agenda = [];
            controller.state = Model.transition(Model.CLOSED, "clock");
        }
        function test_hover_peek_for_a_day_outside_the_agenda_asks_the_controller() {
            card.peekDay(find("monthName"), "2026-12-01");
            compare(controller.peekFor, "2026-12-01");
            controller.peekEvents = [{ title: "Far", calendar: "Home", color: "", location: "", allDay: true,
                startEpoch: 1, endEpoch: 2 }];
            compare(card.peekEvents.length, 1);
            card.unpeek(find("monthName"));
            compare(card.peekEvents.length, 0);
        }
        // True when the item and every ancestor is visible: what the eye sees.
        function shown(item) {
            for (let i = item; i; i = i.parent) if (!i.visible) return false;
            return true;
        }
        function today() { return Model.dayKey(Math.floor(Date.now() / 1000)); }
        function test_set_up_row_stays_with_a_day_selected() {
            controller.status = { state: "none", kind: "", message: "", lastSuccess: null, lastAttempt: 1 };
            controller.state = Object.assign({}, Model.transition(Model.CLOSED, "clock"), { day: "2026-10-13" });
            controller.dayFor = "2026-10-13"; controller.dayEvents = [];
            waitForRendering(card);
            verify(shown(find("setUpRow")), "the Set up row is hidden while a day is selected");
            verify(!shown(find("newOnDayButton")), "a day view without an account offers New event");
            verify(!find("plusButton").enabled);
        }
        function test_past_hours_are_hatched_today() {
            const key = today();
            controller.now = Model.at(key, 14 * 60);
            controller.state = Object.assign({}, Model.transition(Model.CLOSED, "clock"), { day: key });
            controller.dayFor = key; controller.dayEvents = [];
            waitForRendering(card);
            const hatch = find("pastHatch");
            verify(shown(hatch), "today's past hours have no hatch");
            verify(hatch.width > 0 && hatch.width < find("timelineStrip").width, "the hatch covers only the past: " + hatch.width);
        }
        function test_year_wheel_moves_years() {
            controller.state = Object.assign({}, Model.transition(Model.CLOSED, "clock"), { year: true });
            waitForRendering(card);
            const view = find("yearView");
            mouseWheel(view, 20, 20, 0, 120, 0, 0);
            compare(controller.lastShift, -1);
            mouseWheel(view, 20, 20, 0, -120, 0, 0);
            compare(controller.lastShift, 1);
            controller.state = Model.transition(Model.CLOSED, "clock");
        }
        function test_ticks_follow_the_clock() {
            const key = "2026-10-13";
            controller.state = Object.assign({}, Model.transition(Model.CLOSED, "clock"), { day: key });
            controller.dayFor = key; controller.dayEvents = [];
            controller.clock = "24h";
            waitForRendering(card);
            const h24 = rowsNamed(card, "tick").map(t => t.text);
            verify(h24.length > 1 && h24.every(t => /^\d\d:\d\d$/.test(t)), "24 h ticks: " + h24.join(" | "));
            controller.clock = "12h";
            waitForRendering(card);
            const h12 = rowsNamed(card, "tick").map(t => t.text);
            verify(h12.length > 1 && h12.every(t => /^\d{1,2} \S/.test(t)), "12 h ticks: " + h12.join(" | "));
            verify(h12.some(t => t.indexOf(Qt.locale("it_IT").pmText) >= 0), "no PM tick in 12 h: " + h12.join(" | "));
        }
        function test_12h_time_column_leaves_room_for_the_dot() {
            const key = today();
            controller.clock = "12h";
            controller.now = Model.at(key, 9 * 60);
            controller.agenda = [{ title: "Dentist", calendar: "Home", color: "", location: "", allDay: false,
                startEpoch: Model.at(key, 18 * 60), endEpoch: Model.at(key, 19 * 60) }];
            controller.state = Object.assign({}, Model.transition(Model.CLOSED, "clock"), { unfolded: true });
            waitForRendering(card);
            const row = rowsNamed(card, "eventRow")[0];
            const time = findChild(row, "eventTime"), dot = findChild(row, "eventDot");
            verify(time.implicitWidth <= time.width, "the time text is clipped: " + time.implicitWidth + " > " + time.width);
            verify(dot.mapToItem(row, 0, 0).x >= time.mapToItem(row, time.width, 0).x, "the dot sits under the time");
            verify(row.mapToItem(card, row.width, 0).x <= card.width, "the row leaves the card");
        }
        function test_now_line_follows_the_wall_clock_over_dst() {
            for (const day of ["2026-10-25", "2027-03-28"]) {
                controller.now = Model.at(day, 18 * 60);
                controller.state = Object.assign({}, Model.transition(Model.CLOSED, "clock"), { day: day });
                controller.dayFor = day; controller.dayEvents = [];
                waitForRendering(card);
                const tl = find("timeline");
                const want = (18 - tl.range.from) / (tl.range.to - tl.range.from);
                verify(Math.abs(tl.nowX - want) < 1e-9, day + ": the now line is at " + tl.nowX + ", want " + want);
            }
        }
        function test_late_reply_does_not_replace_a_later_preview() {
            card.peekDay(find("monthName"), "2026-12-01");        // A: not in the agenda, so it waits on the controller
            compare(controller.peekFor, "2026-12-01");
            const soon = "2026-10-13";
            controller.agenda = [{ title: "B", calendar: "Home", color: "", location: "", allDay: true,
                startEpoch: Model.dayStart(soon), endEpoch: Model.dayStart(Model.addDays(soon, 1)) }];
            card.peekDay(find("monthName"), soon);                // B: known, shown at once
            compare(card.peekEvents[0].title, "B");
            controller.peekEvents = [{ title: "A-late", calendar: "Home", color: "", location: "", allDay: true,
                startEpoch: 1, endEpoch: 2 }];                    // A's reply arrives after B
            compare(card.peekEvents[0].title, "B");
            card.unpeek(find("monthName"));
        }
        function test_pointer_lists_only_the_events_under_it() {
            const key = "2026-10-13";
            const mk = (title, from, to) => ({ title: title, calendar: "Home", color: "", location: "", allDay: false,
                startEpoch: Model.at(key, from), endEpoch: Model.at(key, to) });
            controller.dayFor = key; controller.dayEvents = [mk("A", 9 * 60, 12 * 60), mk("B", 11 * 60, 13 * 60)];
            controller.state = Object.assign({}, Model.transition(Model.CLOSED, "clock"), { day: key });
            waitForRendering(card);
            const tl = find("timeline"), strip = find("timelineStrip");
            const block = rowsNamed(card, "timeBlock").find(b => b.modelData.title === "A");
            // Hover at an hour of the strip, as the pointer would be over block A.
            const hoverAt = hour => {
                const x = (hour - tl.range.from) / (tl.range.to - tl.range.from) * strip.width;
                mouseMove(block, block.mapFromItem(strip, x, 0).x, 5);
            };
            hoverAt(9.5);
            compare(card.peekEvents.map(e => e.title).join(), "A");
            hoverAt(11.5);
            compare(card.peekEvents.map(e => e.title).join(), "A,B");
            card.unpeek(block);
        }
    }
}
