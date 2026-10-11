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
        function pickMonth(m) {} function shiftMonth(d) {} function shiftYear(d) {}
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
    }
}
