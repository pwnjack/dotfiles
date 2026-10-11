import QtQuick
import QtTest
import ".."
import "../model.mjs" as Model
import "../controller.js" as Controller

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
        // The draft file is a text target here; the shell writes the same Model.draftToKeep text to draft.json.
        property string draftFileText: ""
        readonly property var draftWriter: ({ setText: function (t) { controller.draftFileText = t; } })
        // The same controller.js the shell runs; only the writer and the cal.sh replies are fakes.
        property int sheetSession: 0
        onStateChanged: Controller.invalidate(controller)
        function keepDraft() { Controller.keepDraft(Model, controller, draftWriter); }
        function act(a) {
            const before = state;
            lastAction = a; state = Model.transition(state, a);
            if (before.sheet && !state.sheet) keepDraft();
        }
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
        function pickMonth(m) { lastMonth = m; }
        function shiftMonth(d) { lastShift = d; Controller.shiftMonth(controller, d); }
        function shiftYear(d) { lastShift = d; Controller.shiftYear(controller, d); }
        function loadMonth() {} function loadYear() {} function loadDay(k) {}
        function flash(t) { highlight = t; }
        function defaults() { return { duration: 60, alert: "15m", calendar: "Home" }; }
        function loadPeek(key) { peekFor = key; }
        function toggleUpcoming() { state = Object.assign({}, state, { unfolded: !state.unfolded }); }
        function openSettings() {}
        property int adds: 0; property int cancels: 0
        property string pickerKey: ""
        function setDraft(d) { draft = d; }
        // The shell's add(): a valid draft, into a calendar that is writable now.
        function add() {
            if (Model.validate(draft).ok && calendars.some(c => c.writable && c.name === draft.calendar)) adds += 1;
        }
        function loadPickerMonth(key) { pickerKey = key; }
        function cancelSheet() { cancels += 1; }
        property string saved: ""; property string removed: ""
        property var lastEdited: null
        function save(scope) { saved = scope; }
        function remove(scope) { removed = scope; }
        // cal.sh inspect is a fake: holdInspect keeps its reply pending until replyInspect.
        property bool holdInspect: false; property int asked: -1; property var inspectEvent: null
        function inspectInfo(e) {
            return { ok: true, alert: "custom", recurring: !!e.recurring, invitation: !!e.invitation, allDay: !!e.allDay, hash: "h" };
        }
        function replyInspect(info) { Controller.inspectReply(Model, controller, asked, inspectEvent, info); }
        // The shell's editEvent: the controller.js path, then the fixture's inspect reply unless it is held.
        function editEvent(e) {
            lastEdited = e; inspectEvent = e;
            Controller.beginEdit(Model, controller, draftWriter, e, s => { asked = s; });
            if (!holdInspect) replyInspect(inspectInfo(e));
        }
        function saveReply(session, title, r) { Controller.updateReply(Model, controller, session, title, r); }
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
        function listed(extra) {
            return Object.assign({ uid: "calc-1", title: "Calcetto", location: "", calendar: "Home", color: "#ff9f0a",
                startEpoch: Math.floor(new Date(2026, 9, 20, 20, 0).getTime() / 1000),
                endEpoch: Math.floor(new Date(2026, 9, 20, 22, 30).getTime() / 1000), allDay: false, recurring: true }, extra || {});
        }
        // An edit opens with its layouts settled, as on screen, before a test clicks inside it.
        function openEvent(e) { controller.editEvent(e); waitForRendering(card); }
        function test_edit_repeating() {
            controller.state = Model.transition(Model.CLOSED, "clock");
            controller.saved = ""; controller.removed = "";
            openEvent(listed());
            compare(find("sheetTitle").text, "Edit event");
            compare(find("addLabel").text, "Done");
            compare(find("titleField").text, "Calcetto");
            compare(find("addButton").visible, true);
            compare(find("addButton").enabled, true);
            verify(!find("startDate").enabled);
            verify(!find("allDaySwitch").enabled);
            compare(find("alertValue").text, "Custom (kept)");
            mouseClick(find("addButton"));
            waitForRendering(card);
            verify(find("scopePrompt").visible);
            verify(find("choice1").visible);
            compare(find("promptQuestion").text, "Save changes to this repeating event?");
            mouseClick(find("choice0"));
            compare(controller.saved, "one");
            verify(!find("scopePrompt").visible);
        }
        function test_edit_one_off_saves_at_once() {
            controller.state = Model.transition(Model.CLOSED, "clock");
            controller.saved = "";
            openEvent(listed({ recurring: false }));
            verify(find("startDate").enabled);
            mouseClick(find("addButton"));
            verify(!find("scopePrompt").visible);
            compare(controller.saved, "all");
        }
        function test_calendar_change_offers_all_only() {
            controller.state = Model.transition(Model.CLOSED, "clock");
            controller.calendars = [{ name: "Home", color: "#ff9f0a", writable: true },
                { name: "Work", color: "#3366ff", writable: true }];
            controller.saved = "";
            openEvent(listed());
            controller.draft = Object.assign({}, controller.draft, { calendar: "Work" });
            mouseClick(find("addButton"));
            waitForRendering(card);
            waitForRendering(card);
            verify(find("scopePrompt").visible);
            compare(find("promptQuestion").text, "Save changes to this repeating event?");
            verify(find("choice0").visible);
            compare(findChild(find("scopePrompt"), "choice1"), null);
            mouseClick(find("choice0"));
            compare(controller.saved, "all");
        }
        function test_escape_closes_the_prompt_first() {
            controller.state = Model.transition(Model.CLOSED, "clock");
            controller.saved = "";
            openEvent(listed());
            mouseClick(find("addButton"));
            waitForRendering(card);
            verify(find("scopePrompt").visible);
            keyClick(Qt.Key_Escape);
            verify(!find("scopePrompt").visible);
            compare(controller.saved, "");
            compare(controller.state.sheet, true);
        }
        function test_delete_one_off() {
            controller.state = Model.transition(Model.CLOSED, "clock");
            controller.removed = "";
            openEvent(listed({ recurring: false }));
            mouseClick(find("deleteButton"));
            waitForRendering(card);
            compare(find("promptQuestion").text, "Delete event?");
            mouseClick(find("choice0"));
            compare(controller.removed, "all");
        }
        function test_delete_repeating_asks_which_events() {
            controller.state = Model.transition(Model.CLOSED, "clock");
            controller.removed = "";
            openEvent(listed());
            mouseClick(find("deleteButton"));
            waitForRendering(card);
            compare(find("promptQuestion").text, "Delete this repeating event?");
            mouseClick(find("choice1"));
            compare(controller.removed, "all");
        }
        function test_invitation_is_read_only() {
            controller.state = Model.transition(Model.CLOSED, "clock");
            openEvent(listed({ invitation: true, recurring: false }));
            compare(find("readOnlyLine").text, "Invitation · reply or change it on your iPhone");
            verify(find("readOnlyLine").visible);
            verify(!find("deleteButton").visible);
            verify(!find("addButton").visible);
            verify(!find("titleField").enabled);
            verify(!find("startTime").enabled);
        }
        function test_read_only_calendar_says_so() {
            controller.state = Model.transition(Model.CLOSED, "clock");
            openEvent(listed({ calendar: "Holidays", recurring: false }));
            controller.draft = Object.assign({}, controller.draft, { readOnly: true, invitation: false });
            compare(find("readOnlyLine").text, "Read-only calendar");
            verify(!find("locationField").enabled);
        }
        function test_no_self_clash() {
            controller.state = Model.transition(Model.CLOSED, "clock");
            openEvent(listed());
            controller.dayFor = "2026-10-20"; controller.dayEvents = [listed()];
            compare(find("overlap0"), null);
        }
        function test_clash_with_another_event_is_shown() {
            controller.state = Model.transition(Model.CLOSED, "clock");
            openEvent(listed({ recurring: false }));
            controller.dayFor = "2026-10-20";
            controller.dayEvents = [listed({ uid: "other", title: "Dentist", recurring: false })];
            waitForRendering(card);
            verify(find("overlap0").visible);
            verify(find("overlap0").text.indexOf("Dentist") > 0);
        }
        function test_timeline_block_click_opens_the_event() {
            controller.state = Object.assign({}, Model.transition(Model.CLOSED, "clock"), { day: "2026-10-20" });
            controller.dayFor = "2026-10-20"; controller.dayEvents = [listed({ recurring: false })];
            waitForRendering(card);
            controller.lastEdited = null;
            const blocks = rowsNamed(find("timeline"), "timeBlock");
            verify(blocks.length > 0);
            mouseClick(blocks[0]);
            compare(controller.lastEdited.title, "Calcetto");
        }
        function test_event_row_click_opens_the_event() {
            controller.state = Object.assign({}, Model.transition(Model.CLOSED, "clock"), { day: "2026-10-20" });
            controller.dayFor = "2026-10-20"; controller.dayEvents = [listed({ recurring: false })];
            waitForRendering(card);
            controller.lastEdited = null;
            const rows = rowsNamed(card, "eventRow");
            verify(rows.length > 0);
            mouseClick(rows[0]);
            compare(controller.lastEdited.title, "Calcetto");
        }
        function test_sheet_timeline_does_not_open_another_event() {
            controller.state = Model.transition(Model.CLOSED, "clock");
            openEvent(listed({ recurring: false }));
            controller.dayFor = "2026-10-20";
            controller.dayEvents = [listed({ uid: "other", title: "Dentist", startEpoch: Math.floor(new Date(2026, 9, 20, 9, 0).getTime() / 1000),
                endEpoch: Math.floor(new Date(2026, 9, 20, 10, 0).getTime() / 1000), recurring: false })];
            waitForRendering(card);
            controller.lastEdited = null;
            const blocks = rowsNamed(find("sheetTimeline"), "timeBlock");
            verify(blocks.length > 0);
            mouseClick(blocks[0]);
            compare(controller.lastEdited, null);
        }
        function test_delete_moved_series_offers_all_only() {
            controller.state = Model.transition(Model.CLOSED, "clock");
            controller.calendars = [{ name: "Home", color: "#ff9f0a", writable: true },
                { name: "Work", color: "#3366ff", writable: true }];
            controller.removed = "";
            openEvent(listed());
            controller.draft = Object.assign({}, controller.draft, { calendar: "Work" });
            mouseClick(find("deleteButton"));
            waitForRendering(card);
            verify(find("scopePrompt").visible);
            compare(find("promptQuestion").text, "Delete this repeating event?");
            verify(find("choice0").visible);
            compare(findChild(find("scopePrompt"), "choice1"), null);
            mouseClick(find("choice0"));
            compare(controller.removed, "all");
        }
        // Finding 5: a typed new event survives an event click and a plain exit, and an edit never writes the file.
        function test_typed_new_event_is_kept_when_an_event_is_clicked() {
            controller.state = Model.openSheet(Model.transition(Model.CLOSED, "clock"));
            controller.draft = Object.assign({}, Model.newDraft(1000, { duration: 60, alert: "15m", calendar: "Home" }), { title: "Match" });
            controller.draftFileText = "";
            waitForRendering(card);
            controller.editEvent(listed({ recurring: false }));
            compare(JSON.parse(controller.draftFileText).title, "Match");
            compare(controller.draft.mode, "edit");
            controller.draftFileText = "";
            controller.editEvent(listed({ recurring: false }));
            compare(controller.draftFileText, "");
        }
        function test_typed_new_event_is_kept_when_the_sheet_is_left() {
            controller.state = Model.openSheet(Model.transition(Model.CLOSED, "clock"));
            controller.draft = Object.assign({}, Model.newDraft(1000, { duration: 60, alert: "15m", calendar: "Home" }), { title: "Match" });
            controller.draftFileText = "";
            controller.act("esc");
            verify(!controller.state.sheet);
            compare(JSON.parse(controller.draftFileText).title, "Match");
        }
        // Finding 3: a reply asked before a month or year shift is dropped, so an old event never opens over the new view.
        function test_delayed_inspect_after_a_month_shift_is_dropped() {
            const month = controller.viewMonth;
            controller.state = Model.transition(Model.CLOSED, "clock");
            controller.draft = null;
            controller.holdInspect = true;
            controller.editEvent(listed());
            controller.shiftMonth(1);
            controller.holdInspect = false;
            controller.replyInspect(controller.inspectInfo(controller.inspectEvent));
            verify(!controller.state.sheet, "a stale inspect reply opened a sheet");
            compare(controller.draft, null);
            controller.viewMonth = month;
        }
        function test_delayed_inspect_after_a_year_shift_is_dropped() {
            const year = controller.viewYear;
            controller.state = Model.transition(Model.CLOSED, "clock");
            controller.draft = null;
            controller.holdInspect = true;
            controller.editEvent(listed());
            controller.shiftYear(-1);
            controller.holdInspect = false;
            controller.replyInspect(controller.inspectInfo(controller.inspectEvent));
            verify(!controller.state.sheet, "a stale inspect reply opened a sheet");
            compare(controller.draft, null);
            controller.viewYear = year;
        }
        // The control: the same delayed reply with no navigation in between still opens the event.
        function test_delayed_inspect_without_navigation_opens_the_event() {
            controller.state = Model.transition(Model.CLOSED, "clock");
            controller.draft = null;
            controller.holdInspect = true;
            controller.editEvent(listed());
            controller.holdInspect = false;
            controller.replyInspect(controller.inspectInfo(controller.inspectEvent));
            verify(controller.state.sheet);
            compare(controller.draft.mode, "edit");
        }
        // An inspect is a read: a failure for an abandoned click leaves no card error and no sheet.
        function test_delayed_inspect_failure_after_a_month_shift_is_dropped() {
            const month = controller.viewMonth;
            controller.state = Model.transition(Model.CLOSED, "clock");
            controller.draft = null;
            controller.holdInspect = true;
            controller.editEvent(listed());
            controller.shiftMonth(1);
            controller.holdInspect = false;
            controller.replyInspect({ ok: false, error: "Could not read the event" });
            verify(!controller.state.sheet, "a stale inspect failure opened a sheet");
            compare(controller.addError, "");
            waitForRendering(card);
            verify(!find("cardError").visible, "a stale inspect failure showed on the card");
            controller.viewMonth = month;
        }
        function test_delayed_inspect_failure_after_a_year_shift_is_dropped() {
            const year = controller.viewYear;
            controller.state = Model.transition(Model.CLOSED, "clock");
            controller.draft = null;
            controller.holdInspect = true;
            controller.editEvent(listed());
            controller.shiftYear(-1);
            controller.holdInspect = false;
            controller.replyInspect({ ok: false, error: "Could not read the event" });
            verify(!controller.state.sheet, "a stale inspect failure opened a sheet");
            compare(controller.addError, "");
            waitForRendering(card);
            verify(!find("cardError").visible, "a stale inspect failure showed on the card");
            controller.viewYear = year;
        }
        function test_delayed_inspect_failure_after_a_day_is_selected_is_dropped() {
            controller.state = Model.transition(Model.CLOSED, "clock");
            controller.draft = null;
            controller.holdInspect = true;
            controller.editEvent(listed());
            controller.selectDay("2026-10-21");
            controller.holdInspect = false;
            controller.replyInspect({ ok: false, error: "Could not read the event" });
            verify(!controller.state.sheet, "a stale inspect failure opened a sheet");
            compare(controller.addError, "");
            waitForRendering(card);
            verify(!find("cardError").visible, "a stale inspect failure showed on the card");
        }
        // The control: a current inspect failure, with no navigation in between, still shows on the card.
        function test_current_inspect_failure_shows_on_the_card() {
            controller.state = Model.transition(Model.CLOSED, "clock");
            controller.draft = null;
            controller.holdInspect = true;
            controller.editEvent(listed());
            controller.holdInspect = false;
            controller.replyInspect({ ok: false, error: "Could not read the event" });
            verify(!controller.state.sheet);
            compare(controller.addError, "Could not read the event");
            waitForRendering(card);
            verify(find("cardError").visible);
            compare(find("cardError").text, "Could not read the event");
            controller.addError = "";
        }
        // A save asked from a sheet that a navigation has since retired: it highlights its event, and leaves the newer view alone.
        function test_stale_save_reply_keeps_the_draft_and_only_highlights() {
            const month = controller.viewMonth;
            controller.state = Model.transition(Model.CLOSED, "clock");
            controller.editEvent(listed());
            const session = controller.sheetSession;
            controller.shiftMonth(1);
            controller.highlight = "";
            controller.saveReply(session, "Calcetto", { ok: true });
            compare(controller.draft.mode, "edit");
            compare(controller.highlight, "Calcetto");
            controller.viewMonth = month;
        }
        function test_failure_with_no_sheet_shows_on_the_card() {
            controller.state = Object.assign({}, Model.transition(Model.CLOSED, "clock"), { day: "2026-10-20" });
            controller.addError = "This event changed on your iPhone; open it again";
            waitForRendering(card);
            verify(find("cardError").visible);
            compare(find("cardError").text, "This event changed on your iPhone; open it again");
            controller.state = Model.openSheet(controller.state);
            waitForRendering(card);
            verify(!find("cardError").visible);
        }

        // The tests share one controller: each starts from the same clock, agenda and month data.
        function cleanup() {
            controller.now = 1000 + 180;
            controller.agenda = []; controller.busy = ({}); controller.counts = ({});
            controller.peekFor = ""; controller.peekEvents = [];
            controller.dayFor = ""; controller.dayEvents = []; controller.clock = "24h";
            controller.status = { state: "ok", kind: "", message: "", lastSuccess: 1000, lastAttempt: 1000 };
            controller.state = Model.transition(Model.CLOSED, "clock");
            controller.draft = null; controller.adds = 0; controller.cancels = 0; controller.pickerKey = "";
            controller.saved = ""; controller.removed = ""; controller.lastEdited = null;
            controller.draftFileText = ""; controller.addError = "";
            controller.calendars = [{ name: "Home", color: "#ff9f0a", writable: true }];
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

        // ── The new-event sheet.
        function openSheet(key, minutes) {
            controller.state = Model.openSheet(Model.transition(Model.CLOSED, "clock"));
            controller.draft = Model.newDraft(Math.floor(new Date(2026, 9, 11, 16, 52).getTime() / 1000),
                { duration: 60, alert: "15m", calendar: "Home" }, key || "2026-10-13", minutes === undefined ? 20 * 60 + 30 : minutes);
            controller.dayFor = controller.draft.startDay;
            controller.dayEvents = [{ title: "Calcetto", calendar: "Home", color: "#ff9f0a", location: "", allDay: false,
                startEpoch: Math.floor(new Date(2026, 9, 13, 20, 0).getTime() / 1000), endEpoch: Math.floor(new Date(2026, 9, 13, 22, 30).getTime() / 1000) }];
            waitForRendering(card);
        }
        // The name of the focused item that has one, so tab order can be read back.
        function focusedName(item) {
            for (const c of item.children) {
                if (c.activeFocus && c.objectName) return c.objectName;
                const n = focusedName(c);
                if (n) return n;
            }
            return "";
        }
        function test_add_disabled_without_title() {
            openSheet();
            verify(!find("addButton").enabled);
            find("titleField").text = "Match";
            verify(find("addButton").enabled);
            keyClick(Qt.Key_Return);
            compare(controller.adds, 1);
        }
        function test_overlap_line() {
            openSheet();
            verify(find("overlap0").text.indexOf("Calcetto") >= 0);
            verify(find("overlap0").text.indexOf("20:00–22:30") >= 0);
        }
        function test_end_before_start_is_struck() {
            openSheet();
            controller.draft = Model.setEnd(controller.draft, controller.draft.start - 600);
            verify(find("endTime").strikeout);
            verify(find("endDate").strikeout);
        }
        function test_all_day_hides_times_and_switches_alerts() {
            openSheet();
            mouseClick(find("allDaySwitch"));
            verify(controller.draft.allDay);
            verify(!find("startTime").visible);
            compare(find("alertValue").text, "On the day (09:00)");
        }
        function test_date_pill_opens_the_picker_and_escape_closes_it_first() {
            openSheet();
            mouseClick(find("startDate"));
            verify(find("startPicker").visible);
            keyClick(Qt.Key_Escape);
            verify(!find("startPicker").visible);
            verify(controller.state.sheet);                  // the sheet itself stays
        }
        function test_time_typing() {
            openSheet();
            mouseClick(find("startTime"));
            const field = find("startTimeField");
            field.selectAll(); keyClick(Qt.Key_1); keyClick(Qt.Key_9); keyClick(Qt.Key_Return);
            compare(Model.minutesOf(controller.draft.start), 19 * 60);
            compare(controller.draft.end - controller.draft.start, 3600);
        }
        function test_italian_date_pill() {
            openSheet();
            compare(find("startDate").text, Qt.locale("it_IT").toString(new Date(2026, 9, 13), "ddd d MMM yyyy"));
        }
        function test_wheel_on_the_start_time_moves_by_fifteen_minutes() {
            openSheet();
            const before = controller.draft.start;
            mouseWheel(find("startTime"), 5, 5, 0, 120, 0, 0);
            compare(controller.draft.start - before, 900);
            compare(controller.draft.end - controller.draft.start, 3600);
        }
        function test_cancel_calls_the_controller() {
            openSheet();
            mouseClick(find("cancelButton"));
            compare(controller.cancels, 1);
        }
        function test_rows_fit_the_card_in_12h_italian() {
            controller.clock = "12h";
            openSheet("2026-09-30", 18 * 60 + 30);
            compare(find("startTime").text, "06:30 " + Qt.locale("it_IT").pmText);
            for (const n of ["startDate", "startTime", "endDate", "endTime"]) {
                const p = find(n);
                const right = p.mapToItem(card, p.width, 0).x;
                verify(right <= card.width - card.px(12), n + " reaches x=" + right + " on a " + card.width + " px card");
            }
        }
        function test_tab_order_runs_to_add() {
            openSheet();
            find("titleField").text = "Match";           // Add is disabled, and so unfocusable, until there is a title
            find("titleField").forceActiveFocus();
            verify(find("addButton").enabled);
            const seen = [];
            for (let i = 0; i < 9; i++) { keyClick(Qt.Key_Tab); seen.push(focusedName(card)); }
            compare(seen.join(), "locationField,allDaySwitch,startDate,startTime,endDate,endTime,calendarValue,alertPill,addButton");
        }
        function test_calendar_menu_lists_only_writable_calendars() {
            openSheet();
            controller.calendars = [{ name: "Home", color: "#ff9f0a", writable: true }, { name: "Work", color: "#00ff00", writable: false }];
            mouseClick(find("calendarValue"));
            verify(shown(find("calendarMenu")));
            compare(rowsNamed(find("calendarMenu"), "menuItem0").length, 1);
            compare(rowsNamed(find("calendarMenu"), "menuItem1").length, 0);
        }
        function test_no_writable_calendar_disables_add() {
            openSheet();
            controller.draft = Object.assign({}, controller.draft, { calendar: "" });
            compare(find("calendarValue").text, "No writable calendar");
            verify(!find("addButton").enabled);
        }
        function test_alert_menu_ticks_the_current_preset() {
            openSheet();
            mouseClick(find("alertPill"));
            verify(shown(find("alertMenu")));
            verify(rowsNamed(find("alertMenu"), "tick4")[0].visible);     // 15m is the fifth timed preset
            verify(!rowsNamed(find("alertMenu"), "tick0")[0].visible);
        }
        // Return on any focused pill adds a valid draft; only Space and click open the controls.
        function test_return_adds_from_each_focused_pill() {
            openSheet();
            find("titleField").text = "Match";
            for (const n of ["startDate", "startTime", "endDate", "endTime", "calendarValue", "alertPill"]) {
                find(n).forceActiveFocus();
                const before = controller.adds;
                keyClick(Qt.Key_Return);
                compare(controller.adds - before, 1, n + " did not add on Return");
            }
            verify(!find("startTimeField").visible && !find("endTimeField").visible, "Return opened a time editor");
            verify(!find("startPicker").visible && !find("endPicker").visible, "Return opened a picker");
            verify(!find("calendarMenu").visible && !find("alertMenu").visible, "Return opened a menu");
        }
        function test_space_still_opens_the_picker() {
            openSheet();
            find("startDate").forceActiveFocus();
            keyClick(Qt.Key_Space);
            verify(find("startPicker").visible);
        }
        function test_return_in_a_time_field_applies_the_time_without_adding() {
            openSheet();
            find("titleField").text = "Match";
            mouseClick(find("startTime"));
            const field = find("startTimeField");
            field.selectAll(); keyClick(Qt.Key_1); keyClick(Qt.Key_9); keyClick(Qt.Key_Return);
            compare(Model.minutesOf(controller.draft.start), 19 * 60);
            compare(controller.adds, 0, "Return in the time editor also added the event");
        }
        function test_escape_in_a_time_field_keeps_the_old_time() {
            openSheet();
            const before = controller.draft.start;
            mouseClick(find("startTime"));
            const field = find("startTimeField");
            field.selectAll(); keyClick(Qt.Key_1); keyClick(Qt.Key_9); keyClick(Qt.Key_Escape);
            compare(controller.draft.start, before);
            verify(!find("startTimeField").visible);
        }
        // A typed time is applied when another pill is clicked, and the clicked control stays open.
        function test_clicking_another_pill_applies_a_typed_time() {
            openSheet();
            mouseClick(find("startTime"));
            const field = find("startTimeField");
            field.selectAll(); keyClick(Qt.Key_1); keyClick(Qt.Key_9);
            mouseClick(find("endDate"));
            compare(Model.minutesOf(controller.draft.start), 19 * 60);
            verify(find("endPicker").visible, "the picker the click opened is closed again");
            verify(!find("startTimeField").visible);
        }
        // The picker takes the keys, and Esc gives focus back to its date pill.
        function test_picker_keys_reach_the_month_grid() {
            for (const pair of [["startDate", "startPicker"], ["endDate", "endPicker"]]) {
                openSheet();
                const pill = find(pair[0]), picker = find(pair[1]);
                mouseClick(pill);
                verify(picker.activeFocus, pair[0] + ": the picker does not have focus");
                const before = picker.month;
                keyClick(Qt.Key_PageDown);
                compare(picker.month, (before + 1) % 12, pair[0] + ": PgDn did not move the picker");
                keyClick(Qt.Key_Escape);
                verify(!picker.visible);
                verify(pill.activeFocus, pair[0] + ": focus did not return to the pill");
            }
        }
        // The picker asks for its own month, and that month's busy dots show when the result lands.
        function test_picker_asks_for_its_month_and_shows_its_busy_dots() {
            openSheet();
            mouseClick(find("startDate"));
            compare(controller.pickerKey, "2026-10");
            keyClick(Qt.Key_PageDown);
            compare(controller.pickerKey, "2026-11");
            // What readerDone stores when the requested month arrives.
            const b = Object.assign({}, controller.busy); b["2026-11"] = [5]; controller.busy = b;
            verify(findChild(find("startPicker"), "dot-2026-11-5").visible, "no busy dot for the requested month");
        }
        // A new draft replaces the fields of the last one, even while the sheet is already showing.
        function test_a_new_draft_replaces_the_fields_of_the_last_one() {
            openSheet();
            find("titleField").text = "Old title";
            find("locationField").text = "Old place";
            controller.state = Model.transition(controller.state, "esc");
            openSheet("2026-10-14");
            compare(find("titleField").text, "");
            compare(find("locationField").text, "");
            verify(!find("addButton").enabled);
        }
        // A restored draft naming a calendar that is no longer writable cannot be added.
        function test_stale_calendar_selection_disables_add() {
            openSheet();
            find("titleField").text = "Match";
            verify(find("addButton").enabled);
            controller.calendars = [{ name: "Work", color: "#00ff00", writable: true }];
            verify(!find("addButton").enabled);
            compare(find("calendarValue").text, "No writable calendar");
            find("titleField").forceActiveFocus();
            keyClick(Qt.Key_Return);
            compare(controller.adds, 0);
            controller.calendars = [];
            verify(!find("addButton").enabled);
        }
        // A long conflict title wraps inside the card, and its time stays readable.
        function test_long_conflict_title_stays_inside_the_card() {
            openSheet();
            controller.dayEvents = [{ title: "Riunione ".repeat(30), calendar: "Home", color: "#ff9f0a", location: "", allDay: false,
                startEpoch: Math.floor(new Date(2026, 9, 13, 20, 0).getTime() / 1000), endEpoch: Math.floor(new Date(2026, 9, 13, 22, 30).getTime() / 1000) }];
            waitForRendering(card);
            const warn = find("overlap0");
            const right = warn.mapToItem(card, warn.width, 0).x;
            verify(right <= card.width - card.px(12), "the warning reaches x=" + right + " on a " + card.width + " px card");
            verify(warn.lineCount > 1, "the warning does not wrap");
            verify(warn.text.indexOf("20:00–22:30") >= 0, "the time is cut off");
        }
    }
}
