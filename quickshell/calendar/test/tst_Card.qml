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
        readonly property var draftWriter: ({ setText: function (t) { controller.draftFileText = t; }, text: function () { return controller.draftFileText; } })
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
        // The shell's selection, through the same controller.js functions.
        function selectDay(k) { Controller.selectDay(controller, k); }
        function closeDay() { lastAction = "closeDay"; Controller.closeDay(controller); }
        function showYear() { state = Object.assign({}, state, { year: true }); }
        property int lastShift: 0; property int lastMonth: -1
        property string peekFor: ""; property var peekEvents: []
        function pickMonth(m) { lastMonth = m; }
        function shiftMonth(d) { lastShift = d; Controller.shiftMonth(controller, d); }
        function shiftYear(d) { lastShift = d; Controller.shiftYear(controller, d); }
        function loadMonth() {} function loadYear() {} function loadDay(k) {}
        function flash(t) { highlight = t; }
        // The shell's defaults(): the saved default when writable, else the first writable calendar.
        function defaults() { const w = calendars.find(c => c.writable); return { duration: 60, alert: "15m", calendar: w ? w.name : "" }; }
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
        // The shell's add and calendar-list replies, and the desktop notice a failure gets once the card is gone.
        property string lastNotice: ""
        function notifyFailure(message) { lastNotice = message; }
        function addReply(session, sent, title, r) { Controller.addReply(Model, controller, session, sent, title, r, draftWriter); }
        function calendarsReply(list) { Controller.calendarsReply(Model, controller, list); }
        // The shell's write count, dismissal and quit, through the same controller.js functions.
        property int pendingWrites: 0; property bool quitting: false; property bool closing: false; property int quitCalls: 0
        function quit() { quitCalls += 1; }
        function beginWrite() { Controller.beginWrite(controller); }
        function endWrite() { Controller.endWrite(controller); }
        function dismissed() { Controller.dismissed(controller); }
        function reopen() { closing = false; Controller.reopened(controller); }
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
            compare(find("readOnlyLine").text, "Invitation · read-only here");
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
            controller.addError = "This event changed elsewhere since you opened it; open it again";
            waitForRendering(card);
            verify(find("cardError").visible);
            compare(find("cardError").text, "This event changed elsewhere since you opened it; open it again");
            controller.state = Model.openSheet(controller.state);
            waitForRendering(card);
            verify(!find("cardError").visible);
        }

        // The tests share one controller: each starts from the same clock, agenda and month data.
        function cleanup() {
            controller.now = 1000 + 180;
            controller.lastNotice = ""; controller.highlight = ""; controller.addError = "";
            controller.agenda = []; controller.busy = ({}); controller.counts = ({});
            controller.peekFor = ""; controller.peekEvents = [];
            controller.dayFor = ""; controller.dayEvents = []; controller.clock = "24h";
            controller.status = { state: "ok", kind: "", message: "", lastSuccess: 1000, lastAttempt: 1000 };
            controller.state = Model.transition(Model.CLOSED, "clock");
            controller.draft = null; controller.adds = 0; controller.cancels = 0; controller.pickerKey = "";
            controller.saved = ""; controller.removed = ""; controller.lastEdited = null;
            controller.draftFileText = ""; controller.addError = "";
            controller.pendingWrites = 0; controller.quitting = false; controller.closing = false; controller.quitCalls = 0;
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
            wait(250);                  // the frame eases its height over 160 ms; a click lands in the settled card
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
            controller.dayFor = key;
            controller.dayEvents = [{ title: "Call", calendar: "Home", color: "", location: "", allDay: false,
                startEpoch: Model.at(key, 16 * 60), endEpoch: Model.at(key, 17 * 60) }];
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
            tryVerify(() => !find("startPicker").visible, 500);   // it closes with a short slide
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
            tryVerify(() => shown(find("calendarMenu")), 500);
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
            tryVerify(() => shown(find("alertMenu")), 500);
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
            // Opening animates, so anything opened would still be on screen after it settles.
            wait(300);
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
                tryVerify(() => !picker.visible, 500, pair[1] + " stays open after Esc");
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

        // ── A cal.sh add reply belongs to the sheet that asked. A late success never clears or closes a
        // newer draft; a kept copy of the saved event goes, since it would reopen the event.
        function newDraftFor(title) {
            return Object.assign({}, Model.newDraft(1000, { duration: 60, alert: "15m", calendar: "Home" }), { title: title });
        }
        function test_late_add_success_never_clears_a_newer_draft() {
            controller.state = Model.openSheet(Model.transition(Model.CLOSED, "clock"));
            controller.draft = newDraftFor("Match");
            const sent = JSON.stringify(controller.draft);
            const asked = controller.sheetSession;
            controller.act("esc");                                   // the add is still pending; its draft is kept
            compare(controller.draftFileText, sent);
            controller.newEvent();                                   // a newer sheet, typed into
            controller.draft = newDraftFor("Newer");
            controller.addReply(asked, sent, "Match", { ok: true });
            compare(controller.draft.title, "Newer", "a late success replaced the newer draft");
            verify(controller.state.sheet, "a late success closed the newer sheet");
            compare(controller.draftFileText, "", "the kept copy of the saved event is still there");
            compare(controller.highlight, "Match");
        }
        function test_late_add_success_keeps_an_unrelated_kept_draft() {
            controller.state = Model.openSheet(Model.transition(Model.CLOSED, "clock"));
            controller.draft = newDraftFor("Match");
            const sent = JSON.stringify(controller.draft);
            const asked = controller.sheetSession;
            controller.act("esc");
            controller.draftFileText = JSON.stringify(newDraftFor("Unrelated"));   // a different draft was kept since
            controller.addReply(asked, sent, "Match", { ok: true });
            compare(JSON.parse(controller.draftFileText).title, "Unrelated");
        }
        function test_add_success_closes_the_sheet_it_came_from() {
            controller.state = Model.openSheet(Model.transition(Model.CLOSED, "clock"));
            controller.draft = newDraftFor("Match");
            controller.draftFileText = "stale";
            controller.addReply(controller.sheetSession, JSON.stringify(controller.draft), "Match", { ok: true });
            compare(controller.draft, null);
            verify(!controller.state.sheet);
            compare(controller.draftFileText, "");
            compare(controller.highlight, "Match");
        }
        function test_add_success_with_a_draft_edited_meanwhile_keeps_the_sheet() {
            controller.state = Model.openSheet(Model.transition(Model.CLOSED, "clock"));
            controller.draft = newDraftFor("Match");
            const sent = JSON.stringify(controller.draft);
            controller.draft = newDraftFor("Match, moved");           // typed into while the add was pending
            controller.addReply(controller.sheetSession, sent, "Match", { ok: true });
            compare(controller.draft.title, "Match, moved");
            verify(controller.state.sheet);
            compare(controller.highlight, "Match");
        }
        function test_stale_add_failure_is_dropped_from_the_open_sheet_but_reported() {
            controller.state = Model.openSheet(Model.transition(Model.CLOSED, "clock"));
            controller.draft = newDraftFor("Newer");
            controller.addReply(controller.sheetSession - 1, "{}", "Match", { ok: false, error: "iCloud refused" });
            compare(controller.addError, "", "a failed earlier add showed in the newer sheet");
            compare(controller.lastNotice, "iCloud refused", "the failure was lost");
            compare(controller.draft.title, "Newer");
        }
        function test_add_failure_on_the_open_sheet_shows_there() {
            controller.state = Model.openSheet(Model.transition(Model.CLOSED, "clock"));
            controller.draft = newDraftFor("Match");
            controller.addReply(controller.sheetSession, JSON.stringify(controller.draft), "Match", { ok: false, error: "iCloud refused" });
            compare(controller.addError, "iCloud refused");
            compare(controller.lastNotice, "", "a failure the sheet shows also went to the desktop");
            verify(controller.state.sheet);
        }
        function test_add_failure_after_the_card_closed_is_reported_to_the_desktop() {
            controller.state = Model.CLOSED;
            controller.addReply(controller.sheetSession, "{}", "Match", { ok: false, error: "iCloud refused" });
            compare(controller.lastNotice, "iCloud refused");
        }

        // An update or delete that fails is reported as an add is: on the open sheet, or on the
        // desktop once the card no longer shows it.
        // Writes and quitting: a dismissed card quits once every write has answered, and a reopened card never quits.
        function test_dismissal_waits_for_every_overlapping_write() {
            controller.beginWrite();              // an add still running
            controller.beginWrite();              // an event saved meanwhile
            controller.closing = true;
            controller.dismissed();
            compare(controller.quitCalls, 0, "quit before any write answered");
            controller.endWrite();
            compare(controller.quitCalls, 0, "quit with a second write still outstanding");
            controller.endWrite();
            compare(controller.quitCalls, 1, "the last reply did not quit the dismissed card");
        }
        function test_dismissal_without_writes_quits_at_once() {
            controller.closing = true;
            controller.dismissed();
            compare(controller.quitCalls, 1);
        }
        function test_reopening_cancels_a_quit_waiting_on_a_write() {
            controller.beginWrite();
            controller.closing = true;
            controller.dismissed();
            controller.reopen();                  // the card comes back before the write answers
            controller.endWrite();
            compare(controller.quitCalls, 0, "the reopened card quit when its old write answered");
            compare(controller.pendingWrites, 0);
            controller.closing = true;            // and it still quits when dismissed again
            controller.dismissed();
            compare(controller.quitCalls, 1);
        }

        function test_update_failure_on_the_open_sheet_shows_there() {
            controller.state = Model.transition(Model.CLOSED, "clock");
            controller.editEvent(listed());
            controller.saveReply(controller.sheetSession, "Calcetto", { ok: false, error: "iCloud refused" });
            compare(controller.addError, "iCloud refused");
            compare(controller.lastNotice, "", "a failure the sheet shows also went to the desktop");
        }
        function test_update_failure_after_the_card_closed_is_reported_to_the_desktop() {
            controller.state = Model.CLOSED;
            controller.saveReply(controller.sheetSession, "Calcetto", { ok: false, error: "iCloud refused" });
            compare(controller.lastNotice, "iCloud refused", "a failed save after the card closed was lost");
        }
        function test_stale_update_failure_is_reported_to_the_desktop() {
            controller.state = Model.transition(Model.CLOSED, "clock");
            controller.editEvent(listed());
            const session = controller.sheetSession;
            controller.shiftMonth(1);
            controller.saveReply(session, "Calcetto", { ok: false, error: "This event changed elsewhere since you opened it; open it again" });
            compare(controller.addError, "", "a failed earlier save showed on the newer view");
            compare(controller.lastNotice, "This event changed elsewhere since you opened it; open it again", "the failure was lost");
        }

        // ── The calendar list. A slow first discovery, a rename, a writability change, and a failed read.
        function test_slow_first_discovery_gives_the_open_sheet_a_calendar() {
            controller.calendars = [];
            controller.state = Model.openSheet(Model.transition(Model.CLOSED, "clock"));
            controller.draft = Object.assign({}, newDraftFor("Match"), { calendar: "" });
            waitForRendering(card);
            verify(!find("addButton").enabled, "no calendar yet, so Add is off");
            controller.calendarsReply([{ name: "Work", color: "#00ff00", writable: true }]);
            compare(controller.draft.calendar, "Work");
            waitForRendering(card);
            verify(find("addButton").enabled, "discovery did not enable Add");
        }
        function test_renamed_calendar_moves_the_new_draft_to_the_default() {
            openSheet();
            controller.draft = Object.assign({}, controller.draft, { title: "Match" });
            controller.calendarsReply([{ name: "Casa", color: "#ff0000", writable: true }]);
            compare(controller.draft.calendar, "Casa");
            waitForRendering(card);
            verify(find("calendarValue").text.indexOf("Casa") === 0, "the menu shows " + find("calendarValue").text);
            verify(find("addButton").enabled);
        }
        function test_writability_change_makes_an_open_edit_read_only() {
            const e = listed({ startEpoch: Math.floor(new Date(2026, 9, 20, 20, 0).getTime() / 1000) });
            controller.draft = Model.draftFromEvent(e, { alert: "15m", recurring: false, invitation: false, hash: "h" }, { alert: "15m" });
            controller.state = Model.openSheet(Model.transition(Model.CLOSED, "clock"));
            controller.calendarsReply([{ name: "Home", color: "#ff9f0a", writable: false }]);
            verify(controller.draft.readOnly, "a calendar turned read-only still offers Done");
            compare(controller.draft.mode, "edit");
            waitForRendering(card);
            verify(!find("addButton").visible);
        }
        function test_failed_calendar_read_keeps_the_list_and_the_draft() {
            openSheet();
            const before = controller.calendars;
            controller.calendarsReply({ ok: false, error: "khal is not installed" });
            compare(controller.calendars, before, "a failed read replaced the list");
            compare(controller.draft.calendar, "Home", "a failed read reset the draft's calendar");
        }

        // ── Polish: one way in and one way out of each section.
        function test_day_header_close_puts_upcoming_back() {
            controller.state = Object.assign({}, Model.transition(Model.CLOSED, "clock"), { day: "2026-10-13" });
            controller.dayFor = "2026-10-13"; controller.dayEvents = [];
            waitForRendering(card);
            verify(!find("todayButton").visible, "a selected day in this month shows Today; the day has its own close");
            const header = find("dayHeader");
            mouseClick(header, header.width - 17, header.height / 2);
            compare(controller.lastAction, "closeDay");
            compare(controller.state.day, null);
            controller.state = Model.transition(Model.CLOSED, "clock");
        }
        function test_second_click_on_the_selected_day_closes_it() {
            controller.state = Model.transition(Model.CLOSED, "clock");
            const month = controller.viewMonth, year = controller.viewYear;
            const key = year + "-" + String(month + 1).padStart(2, "0") + "-15";
            const cell = findCell(key);
            mouseClick(cell);
            compare(controller.state.day, key);
            mouseClick(cell);
            compare(controller.state.day, null, "a second click on the day left it selected");
            compare(controller.viewMonth, month, "closing the day moved the month");
            compare(controller.viewYear, year);
            waitForRendering(card);
            verify(shown(find("upcomingHeader")), "Upcoming did not come back");
        }
        // The month grid cell for a day: the one whose dot is named for it.
        function findCell(key) {
            const [y, m, d] = key.split("-").map(Number);
            return find("dot-" + y + "-" + String(m).padStart(2, "0") + "-" + d).parent;
        }
        function test_day_timeline_click_on_a_gap_adds_nothing() {
            const key = "2026-10-20";
            controller.state = Object.assign({}, Model.transition(Model.CLOSED, "clock"), { day: key });
            controller.dayFor = key; controller.dayEvents = [listed({ recurring: false })];
            waitForRendering(card);
            const strip = find("timelineStrip");
            mouseClick(strip, 4, strip.height / 2);            // 08:00, before Calcetto
            verify(!controller.state.sheet, "a click on the day's timeline opened a new event");
            controller.state = Model.transition(Model.CLOSED, "clock");
        }
        function test_day_with_no_timed_events_has_no_timeline() {
            controller.state = Object.assign({}, Model.transition(Model.CLOSED, "clock"), { day: "2026-10-13" });
            controller.dayFor = "2026-10-13"; controller.dayEvents = [];
            waitForRendering(card);
            verify(!shown(find("timeline")), "an empty day draws an empty strip");
            controller.state = Model.transition(Model.CLOSED, "clock");
        }
        function test_upcoming_chevron_keeps_its_place() {
            const t = Math.floor(Date.now() / 1000);
            controller.now = t;
            controller.agenda = [{ title: "Dentist", calendar: "Home", color: "#ff9f0a", location: "", allDay: false,
                startEpoch: t + 3600, endEpoch: t + 7200 }];
            controller.state = Model.transition(Model.CLOSED, "clock");
            waitForRendering(card);
            const header = find("upcomingHeader");
            const at = () => header.mapToItem(card, header.width, header.height / 2);
            const folded = at();
            controller.toggleUpcoming();
            waitForRendering(card);
            compare(at().x, folded.x);
            compare(find("foldedLine").text, "Upcoming · 7 days");
            mouseClick(header, header.width - 17, header.height / 2);
            verify(!controller.state.unfolded, "the chevron does not fold the list");
            controller.agenda = [];
        }
        function test_sheet_rows_leave_room_around_their_pills() {
            openSheet();
            for (const name of ["calendarValue", "alertPill", "startDate", "endTime"]) {
                const pill = find(name), row = pill.parent.parent;
                const top = pill.mapToItem(row, 0, 0).y;
                verify(top >= 5, name + " sits " + top + " px from its row's top");
                verify(row.height - top - pill.height >= 5, name + " sits too close to its row's bottom");
            }
            controller.state = Model.transition(Model.CLOSED, "clock");
        }
        function test_sheet_timeline_hides_the_event_being_edited() {
            controller.state = Model.transition(Model.CLOSED, "clock");
            const e = listed({ recurring: false });
            openEvent(e);
            controller.dayFor = "2026-10-20"; controller.dayEvents = [e];
            waitForRendering(card);
            compare(rowsNamed(find("sheetTimeline"), "timeBlock").length, 0, "the edited event is drawn under its own draft");
            controller.state = Model.transition(Model.CLOSED, "clock");
        }
        function test_timeline_tick_labels_never_touch() {
            const key = "2026-10-20";
            controller.state = Object.assign({}, Model.transition(Model.CLOSED, "clock"), { day: key });
            controller.dayFor = key;
            // 08–22 (20:00 would crowd 22:00), then 01–24 (21:00 would crowd the clamped 00:00), in both clocks.
            const ranges = [[listed({ recurring: false })],
                [listed({ recurring: false, startEpoch: Model.at(key, 60), endEpoch: Model.at(Model.addDays(key, 1), 0) })]];
            for (const clock of ["24h", "12h"]) for (const events of ranges) {
                controller.clock = clock;
                controller.dayEvents = events;
                waitForRendering(card);
                const ticks = rowsNamed(find("timeline"), "tick").sort((a, b) => a.x - b.x);
                verify(ticks.length > 2);
                for (let i = 1; i < ticks.length; i++)
                    verify(ticks[i].x - (ticks[i - 1].x + ticks[i - 1].implicitWidth) >= 8, clock + ": " + ticks[i - 1].text + " touches " + ticks[i].text);
            }
            controller.clock = "24h";
            controller.state = Model.transition(Model.CLOSED, "clock");
        }

        // ── The sheet's controls open in place: menus float, pickers slide, the time field keeps the pill's box.
        function test_menus_float_over_the_sheet() {
            for (const pair of [["calendarValue", "calendarMenu"], ["alertPill", "alertMenu"]]) {
                controller.state = Model.transition(Model.CLOSED, "clock");   // a change, so openSheet's wait sees a frame
                openSheet();
                const pill = find(pair[0]), menu = find(pair[1]);
                const sheetHeight = find("sheetTitle").parent.parent.height, pillY = pill.mapToItem(card, 0, 0).y;
                mouseClick(pill);
                tryVerify(() => menu.opacity === 1, 500, pair[1] + " did not open");
                compare(pill.mapToItem(card, 0, 0).y, pillY, pair[1] + " moved its own pill");
                compare(find("sheetTitle").parent.parent.height, sheetHeight, pair[1] + " grew the sheet");
                // Inside the sheet, right-aligned with its pill, and clear of it.
                const top = menu.mapToItem(card, 0, 0).y, bottom = top + menu.height, right = menu.mapToItem(card, menu.width, 0).x;
                verify(top >= 0 && bottom <= card.height, pair[1] + " runs off the card: " + top + "–" + bottom);
                compare(Math.round(right), Math.round(pill.mapToItem(card, pill.width, 0).x));
                verify(bottom <= pillY || top >= pillY + pill.height, pair[1] + " covers its pill");
                keyClick(Qt.Key_Escape);
                tryVerify(() => !menu.visible, 500);
                verify(pill.activeFocus, pair[0] + ": focus did not return to the pill");
                verify(controller.state.sheet, "Esc on the menu left the sheet");
            }
        }
        function test_menu_keys_choose() {
            openSheet();
            mouseClick(find("alertPill"));
            keyClick(Qt.Key_Down); keyClick(Qt.Key_Return);            // 15 minutes → 30 minutes
            compare(controller.draft.alert, "30m");
            tryVerify(() => !find("alertMenu").visible, 500);
            compare(controller.adds, 0, "Return in the menu also added the event");
        }
        function test_click_outside_a_menu_only_closes_it() {
            openSheet();
            mouseClick(find("calendarValue"));
            tryVerify(() => find("calendarMenu").opacity === 1, 500);
            mouseClick(find("allDaySwitch"));
            tryVerify(() => !find("calendarMenu").visible, 500);
            verify(!controller.draft.allDay, "the click that closed the menu also flipped All day");
        }
        function test_time_field_keeps_the_pill_box() {
            for (const clock of ["24h", "12h"]) {
                controller.clock = clock;
                openSheet();
                const pill = find("startTime"), w = pill.width, h = pill.height, x = pill.mapToItem(card, 0, 0).x;
                mouseClick(pill);
                const field = find("startTimeField");
                waitForRendering(card);                    // the row lays the field out on the next frame
                verify(field.visible);
                verify(Math.abs(field.width - w) <= 1, clock + ": the field is " + field.width + " px for a " + w + " px pill");
                compare(field.height, h);
                verify(Math.abs(field.mapToItem(card, 0, 0).x - x) <= 1, clock + ": the field moved from x=" + x + " to x=" + field.mapToItem(card, 0, 0).x);
                keyClick(Qt.Key_Escape);
            }
            controller.clock = "24h";
        }

        function test_backtab_in_a_menu_never_adds() {
            openSheet();
            find("titleField").text = "Match";
            mouseClick(find("alertPill"));
            keyClick(Qt.Key_Backtab); keyClick(Qt.Key_Tab); keyClick(Qt.Key_Down); keyClick(Qt.Key_Return);
            compare(controller.adds, 0, "Return after Shift+Tab in the menu added the event");
            compare(controller.draft.alert, "30m");
        }
        function test_menu_follows_its_pill_while_a_picker_closes() {
            controller.state = Model.transition(Model.CLOSED, "clock");
            openSheet();
            mouseClick(find("startDate"));
            wait(300);                                       // the picker is fully open
            const pill = find("calendarValue"), menu = find("calendarMenu");
            mouseClick(pill);
            wait(400);                                       // the picker has closed under it
            const pillTop = pill.mapToItem(card, 0, 0).y, top = menu.mapToItem(card, 0, 0).y;
            const gap = menu.above ? pillTop - (top + menu.height) : top - (pillTop + pill.height);
            verify(gap >= 0 && gap <= 6, "the menu is " + gap + " px from its pill");
        }
        function test_click_outside_the_sheet_or_card_only_closes_the_menu() {
            openSheet();
            mouseClick(find("calendarValue"));
            tryVerify(() => find("calendarMenu").opacity === 1, 500);
            mouseClick(card, 5, 5);                          // the card's padding, outside the sheet
            tryVerify(() => !find("calendarMenu").visible, 500);
            mouseClick(find("calendarValue"));
            tryVerify(() => find("calendarMenu").opacity === 1, 500);
            verify(card.closePopup(), "a click outside the card did not go to the menu first");
            verify(controller.state.sheet);
            verify(!card.closePopup(), "with no menu open, a click outside must reach the card");
        }
        function test_menus_fit_a_short_window_and_many_calendars() {
            controller.calendars = Array.from({ length: 20 }, (_, i) => ({ name: "Calendario numero " + i + " con un nome lungo", color: "#ff9f0a", writable: true }));
            host.height = 420;
            for (const pair of [["calendarValue", "calendarMenu"], ["alertPill", "alertMenu"]]) {
                controller.state = Model.transition(Model.CLOSED, "clock");
                openSheet();
                controller.draft = Object.assign({}, controller.draft, { calendar: controller.calendars[0].name });
                tryVerify(() => card.height <= host.height, 1000);
                const pill = find(pair[0]), menu = find(pair[1]);
                pill.forceActiveFocus(); keyClick(Qt.Key_Space);
                tryVerify(() => menu.opacity === 1, 500);
                const pr = pill.mapToItem(card, pill.width, 0).x;
                verify(pr <= card.width - card.px(16), pair[0] + " runs past the card: right edge at " + pr);
                const top = menu.mapToItem(card, 0, 0).y, left = menu.mapToItem(card, 0, 0).x;
                verify(top >= 0 && top + menu.height <= card.height, pair[1] + " runs off the card: " + top + "+" + menu.height + " of " + card.height);
                verify(left >= 0 && left + menu.width <= card.width, pair[1] + " is wider than the card");
                keyClick(Qt.Key_Escape);
                tryVerify(() => !menu.visible, 500);
            }
            controller.calendars = [{ name: "Home", color: "#ff9f0a", writable: true }];
            controller.state = Model.transition(Model.CLOSED, "clock");
            host.height = 900;
            wait(300);                                      // the next test starts from a settled card
        }
        function test_time_field_keeps_its_size_while_typing() {
            openSheet();
            mouseClick(find("startTime"));
            const field = find("startTimeField");
            waitForRendering(card);
            const w = field.width, x = field.mapToItem(card, 0, 0).x;
            field.selectAll(); keyClick(Qt.Key_1); keyClick(Qt.Key_1); keyClick(Qt.Key_Colon); keyClick(Qt.Key_3); keyClick(Qt.Key_0);
            keyClick(Qt.Key_Space); keyClick(Qt.Key_P); keyClick(Qt.Key_M);
            waitForRendering(card);
            compare(field.width, w, "the field grew while typing");
            compare(field.mapToItem(card, 0, 0).x, x, "the field moved while typing");
            keyClick(Qt.Key_Return);
            compare(Model.minutesOf(controller.draft.start), 23 * 60 + 30);
        }

        // The date pickers slide: partway through opening and closing, their box is between closed and open.
        function test_date_picker_opens_and_closes_smoothly() {
            for (const pair of [["startDate", "startPicker"], ["endDate", "endPicker"]]) {
                controller.state = Model.transition(Model.CLOSED, "clock");
                openSheet();
                const box = find(pair[1]).parent.parent;            // MonthGrid -> holder -> Reveal
                compare(box.height, 0);
                mouseClick(find(pair[0]));
                wait(70);
                verify(box.height > 0 && box.height < box.fullHeight, pair[1] + " snapped open: " + box.height + " of " + box.fullHeight);
                tryVerify(() => Math.abs(box.height - box.fullHeight) < 0.5, 1000, pair[1] + " never finished opening: " + box.height + " of " + box.fullHeight);
                keyClick(Qt.Key_Escape);
                wait(70);
                verify(box.height > 0 && box.height < box.fullHeight, pair[1] + " snapped shut: " + box.height);
                tryVerify(() => box.height < 0.5, 1000, pair[1] + " never finished closing: " + box.height);
            }
        }
        function test_return_in_a_fresh_picker_confirms_the_date_and_never_adds() {
            openSheet();
            find("titleField").text = "Match";
            const day = controller.draft.startDay;
            mouseClick(find("startDate"));
            keyClick(Qt.Key_Return);
            compare(controller.adds, 0, "Return in the picker added the event");
            compare(controller.draft.startDay, day);
            tryVerify(() => !find("startPicker").visible, 500, "Return did not close the picker");
            mouseClick(find("startDate"));
            mouseClick(find("addButton"));
            compare(controller.adds, 1, "Add does nothing while a picker is open");
        }
        function test_menu_survives_the_sheet_shrinking_under_it() {
            host.height = 420;
            controller.state = Model.transition(Model.CLOSED, "clock");
            openSheet();
            tryVerify(() => card.height <= host.height, 1000);
            mouseClick(find("startDate"));
            wait(300);
            const scroll = find("sheetScroll");
            scroll.contentY = scroll.contentHeight - scroll.height;     // down to Calendar, the picker open above
            waitForRendering(card);
            mouseClick(find("calendarValue"));
            wait(400);                                                    // the picker has closed; the sheet clamped its scroll
            verify(find("calendarMenu").open, "the menu closed itself as the sheet shrank");
            compare(find("calendarMenu").opacity, 1);
            keyClick(Qt.Key_Escape);
            controller.state = Model.transition(Model.CLOSED, "clock");
            host.height = 900;
            wait(300);
        }

        // ── The card's height is bounded by the screen, and its reading views scroll inside that.
        function test_thirty_upcoming_events_stay_inside_a_small_window() {
            const t = Math.floor(Date.now() / 1000);
            controller.now = t;
            controller.agenda = Array.from({ length: 30 }, (_, i) => ({ uid: "u" + i, title: "Evento " + i, calendar: "Home",
                color: "#ff9f0a", location: "", allDay: false, startEpoch: t + 600 + i * 3600, endEpoch: t + 1200 + i * 3600 }));
            controller.state = Object.assign({}, Model.transition(Model.CLOSED, "clock"), { unfolded: true });
            host.height = 900;
            waitForRendering(card);
            // The frame eases its height over 160 ms: judge the settled size.
            tryVerify(() => card.height <= host.height, 1000, "the card is " + card.height + " px in a " + host.height + " px window");
            const scroller = find("scroller");
            verify(scroller.contentHeight > scroller.height, "the upcoming list does not scroll");
            const rows = rowsNamed(card, "eventRow");
            const last = rows[rows.length - 1];
            scroller.contentY = scroller.contentHeight - scroller.height;
            waitForRendering(card);
            // The row, inside the viewport the scroller shows, is reached by scrolling down.
            const top = last.mapToItem(scroller, 0, 0).y;
            verify(top >= 0 && top + last.height <= scroller.height, "the last row is at " + top + " in a " + scroller.height + " px viewport");
            scroller.contentY = 0;
            controller.agenda = [];
            controller.state = Model.transition(Model.CLOSED, "clock");
            host.height = 900;
        }
        function test_short_window_keeps_the_sheet_top_bar_visible() {
            host.height = 260;
            openSheet();
            waitForRendering(card);
            tryVerify(() => card.height <= host.height, 1000, "the sheet is " + card.height + " px in a " + host.height + " px window");
            const bar = find("cancelButton");
            const top = bar.mapToItem(card, 0, 0).y;
            verify(top >= 0 && top + bar.height <= card.height, "the top bar is off the card");
            verify(find("addButton").visible, "the Add button is off the card");
            host.height = 900;
        }
    }
}
