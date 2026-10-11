pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "model.mjs" as Model
import "controller.js" as Controller

// The calendar card. Started by scripts/hyprland/calendar-card.sh; exits on
// close. Data: agenda.json/status.json (rendered by scripts/calendar/sync.sh,
// watched here) and scripts/calendar/cal.sh for days, months and adds.
ShellRoot {
    id: root
    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    readonly property string runtimeDir: Quickshell.env("CALENDAR_RUNTIME_DIR") || Quickshell.env("XDG_RUNTIME_DIR") + "/calendar"
    readonly property string calSh: configDir + "/scripts/calendar/cal.sh"
    readonly property color background: Quickshell.env("CALENDAR_BACKGROUND") || "#05090c"
    readonly property color foreground: Quickshell.env("CALENDAR_FOREGROUND") || "#cfddde"
    readonly property color accent: Quickshell.env("CALENDAR_ACCENT") || "#6097a1"
    readonly property color accentInk: Quickshell.env("CALENDAR_ON_ACCENT") || "#05090c"
    readonly property string monoFont: Quickshell.env("CALENDAR_FONT") || "monospace"
    readonly property bool barAtBottom: Quickshell.env("CALENDAR_BAR_POSITION") === "bottom"
    readonly property string clock: Quickshell.env("CALENDAR_CLOCK") === "12h" ? "12h" : "24h"
    readonly property var locale: Qt.locale(Quickshell.env("CALENDAR_LOCALE") || "en_US")
    readonly property real uiScale: 1

    property var state: Model.CLOSED
    // Every state change (a sheet opens, closes or is replaced, or the card is
    // navigated) starts a new session: a cal.sh reply asked in an earlier one is
    // stale. controller.js's invalidate() also runs on each month or year shift.
    property int sheetSession: 0
    onStateChanged: Controller.invalidate(root)
    property bool closing: false
    property double openedAt: 0
    property bool syncGaveUp: false     // sync.sh waits up to 120 s for its lock; past that, show what we have
    property double now: Date.now() / 1000
    property var agenda: []
    property var status: null
    property var calendars: []
    property var dayEvents: []          // the selected day's (or the sheet's start day's) events
    property string dayFor: ""
    property string peekFor: ""         // the day the newest hover peek asked for
    property var peekEvents: []         // its events, once read
    property var busy: ({})             // "YYYY-MM" -> [day numbers]
    property var counts: ({})           // "YYYY" -> [12 counts]
    property var draft: null
    property string addError: ""
    property string highlight: ""       // title of an event just added, briefly
    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth()

    // The helpers print {"ok":false,"error":…} on failure; anything that is not
    // the expected array reads as empty rather than throwing.
    function asArray(value) { return Array.isArray(value) ? value : []; }

    function act(action) {
        const before = state;
        const next = Model.transition(state, action);
        if (!next.open) { close(); return; }
        if (!before.open) open();
        if (before.sheet && !next.sheet) keepDraft();      // Esc, a bar segment or a click leaves the sheet
        if (next.sheet && !before.sheet) startSheet(next.day);
        state = next;
    }
    function keepDraft() { Controller.keepDraft(Model, root, draftFile); }
    function open() {
        const focused = Hyprland.focusedMonitor;
        window.screen = Quickshell.screens.find(s => focused && s.name === focused.name) || Quickshell.screens[0];
        openedAt = Date.now() / 1000;
        closing = false;
        syncGaveUp = false;
        syncGiveUp.restart();
        const today = new Date();
        viewYear = today.getFullYear(); viewMonth = today.getMonth();
        agendaFile.reload(); statusFile.reload();
        readAgenda(); readStatus();
        syncer.running = true;
        loadMonth(); loadCalendars();
        card.appear();
    }
    function close() {
        keepDraft();
        state = Model.CLOSED;
        closing = true;
        card.disappear();
    }
    function startSheet(dayKey, minutes) {
        let restored = null;
        try { restored = JSON.parse(draftFile.text()); } catch (e) { restored = null; }
        if (restored && !dayKey && minutes === undefined) draft = restored;
        else draft = Model.newDraft(Date.now() / 1000, defaults(), dayKey || null, minutes);
        loadDay(draft.startDay);
    }
    // The sheet's edits come back here: a new start day reloads the timeline's events.
    function setDraft(d) {
        const dayChanged = !draft || draft.startDay !== d.startDay;
        draft = d;
        if (dayChanged) loadDay(d.startDay);
    }
    function newEvent(dayKey, minutes) {        // "+", "New event on …", a timeline gap
        state = Model.openSheet(state);
        startSheet(dayKey, minutes);
    }
    // A click on a listed event: read it with cal.sh inspect, then open it for editing.
    function editEvent(e) {
        if (!e || !e.uid || inspector.running) return;
        Controller.beginEdit(Model, root, draftFile, e, session => {   // keeps a typed new-event draft first
            inspector.event = e;
            inspector.session = session;
            inspector.command = [calSh, "inspect", e.calendar, e.uid, String(e.startEpoch)];
            inspector.running = true;
        });
    }
    function save(scope) {
        if (!draft || draft.mode !== "edit") { add(); return; }
        if (!Model.validate(draft).ok || updater.running) return;
        addError = "";
        updater.request = JSON.stringify({ calendar: draft.originalCalendar, uid: draft.uid, occurrence: draft.occurrence,
            scope: scope || "all", hash: draft.hash, moveTo: draft.calendar !== draft.originalCalendar ? draft.calendar : "",
            changes: Model.changesOf(draft) });
        updater.title = draft.title.trim();
        updater.session = sheetSession;
        updater.command = [calSh, "update"];
        beginWrite();
        updater.running = true;
    }
    function remove(scope) {
        if (!draft || draft.mode !== "edit" || updater.running) return;
        addError = "";
        updater.request = JSON.stringify({ calendar: draft.originalCalendar, uid: draft.uid, occurrence: draft.occurrence,
            scope: scope || "all", hash: draft.hash });
        updater.title = "";
        updater.session = sheetSession;
        updater.command = [calSh, "delete"];
        beginWrite();
        updater.running = true;
    }
    // A write still in flight when the card is dismissed must answer before the shell quits,
    // so its result (or failure) is not lost with the window.
    property bool writePending: false
    property bool quitting: false
    function beginWrite() { writePending = true; }
    function endWrite() { writePending = false; if (quitting) Qt.quit(); }
    // A failure the card can no longer show goes to the desktop instead.
    function notifyFailure(message) { Quickshell.execDetached(["notify-send", "-a", "Calendar", "Calendar", message]); }
    function defaults() {
        const writable = calendars.filter(c => c.writable);
        const wanted = optionDefault.text().trim();
        return {
            duration: Number(optionDuration.text().trim()) || 60,
            alert: optionAlert.text().trim() || "15m",
            calendar: writable.some(c => c.name === wanted) ? wanted : (writable.length ? writable[0].name : ""),
        };
    }
    function readAgenda() { try { agenda = asArray(JSON.parse(agendaFile.text())); } catch (e) { agenda = []; } }
    function readStatus() { try { status = JSON.parse(statusFile.text()); } catch (e) { status = null; } }
    // A reader runs one cal.sh verb at a time. The request's key is echoed on the
    // first output line, so a result is stored under the key it was asked for,
    // whatever was requested while it ran; the newest request runs when it ends.
    function startReader(reader, key) {
        if (reader.running) { reader.queued = key; return; }
        reader.queued = "";
        reader.command = ["bash", "-c", 'printf "%s\\n" "$2"; "$1" "$3" "$2"', "bash", calSh, key, reader.verb];
        reader.running = true;
    }
    function readerDone(verb, text) {
        const cut = text.indexOf("\n");
        if (cut < 0) return;
        const key = text.slice(0, cut), body = text.slice(cut + 1);
        if (verb === "month") { const b = Object.assign({}, busy); b[key] = parseBusy(body); busy = b; }
        else if (verb === "year") { const c = Object.assign({}, counts); c[key] = parseCounts(body); counts = c; }
        else if (verb === "peek") { if (key === peekFor) peekEvents = asArray(parseJson(body)); }   // only the newest hover's day is kept
        else if (key === state.day || (state.sheet && draft && key === draft.startDay)) { dayEvents = asArray(parseJson(body)); dayFor = key; }   // a day neither view shows is dropped
    }
    // The helpers print {"ok":false,"error":…} on failure: any other shape reads as empty.
    function parseJson(body) { try { return JSON.parse(body); } catch (e) { return null; } }
    function parseBusy(body) { const r = parseJson(body); return r && Array.isArray(r.busy) ? r.busy : []; }
    function parseCounts(body) { const r = parseJson(body); return r && Array.isArray(r.counts) && r.counts.length === 12 ? r.counts : []; }
    function loadMonth() {
        startReader(monthReader, viewYear + "-" + String(viewMonth + 1).padStart(2, "0"));
    }
    function loadYear() { startReader(yearReader, String(viewYear)); }
    // The new-event picker's own month ("YYYY-MM"): its own reader, so the card's month is never waiting on it.
    function loadPickerMonth(key) { startReader(pickerReader, key); }
    function loadDay(key) { if (key) startReader(dayReader, key); }
    // A hover peek on a day past the agenda's window. Its own reader, so it never overwrites the selected day.
    function loadPeek(key) { peekFor = key; startReader(peekReader, key); }
    // A publication that lands mid-read queues one more read, so the list is never older than the last sync.
    function loadCalendars() {
        if (calendarReader.running) { calendarReader.queued = true; return; }
        calendarReader.queued = false;
        calendarReader.running = true;
    }
    function shiftMonth(delta) { Controller.shiftMonth(root, delta); }
    function shiftYear(delta) { Controller.shiftYear(root, delta); }
    function flash(title) { highlight = title; if (title) unhighlight.restart(); }
    function goToday() {
        const d = new Date();
        viewYear = d.getFullYear(); viewMonth = d.getMonth();
        state = Object.assign({}, state, { day: null, year: false });
        loadMonth();
    }
    function selectDay(key) { state = Object.assign({}, state, { day: key, year: false }); loadDay(key); }
    function showYear() { state = Object.assign({}, state, { year: true }); loadYear(); }
    function pickMonth(m) { viewMonth = m; state = Object.assign({}, state, { year: false }); loadMonth(); }
    function toggleUpcoming() { state = Object.assign({}, state, { unfolded: !state.unfolded }); }
    // Cancel drops a new event's draft; an edit never touches draft.json.
    function cancelSheet() {
        if (!draft || draft.mode !== "edit") draftFile.setText("");
        draft = null;
        act("esc");
    }
    function add() {
        const writable = draft && calendars.some(c => c.writable && c.name === draft.calendar);
        if (!draft || !Model.validate(draft).ok || !writable || adder.running) return;
        addError = "";
        const nowS = Math.floor(Date.now() / 1000);
        adder.request = JSON.stringify({ calendar: draft.calendar, ics: Model.buildIcs(draft, nowS, Model.newUid(nowS)) });
        adder.title = draft.title.trim();
        adder.session = sheetSession;
        adder.sent = JSON.stringify(draft);
        beginWrite();
        adder.running = true;
    }
    function openSettings() {
        settingsLauncher.running = true;
        close();
    }
    function headerStatus() {
        if (!syncGaveUp && (!status || (status.lastAttempt || 0) < openedAt - 1)) return "syncing…";
        if (!status || status.state === "none") return "Not signed in";
        if (status.state === "failed") {
            if (status.kind === "auth") return "Sign-in rejected · Fix in Settings";
            const t = status.lastSuccess ? Model.formatTime(Model.minutesOf(status.lastSuccess), clock, locale.amText, locale.pmText) : "";
            return status.kind === "network" ? (t ? "Offline · showing events from " + t : "Offline") : status.message;
        }
        const ago = Math.round((now - (status.lastSuccess || now)) / 60);
        return "iCloud · " + (ago <= 0 ? "synced just now" : "synced " + ago + " min ago");
    }
    Component.onCompleted: act(({ month: "clock", upcoming: "pill", "new": "keybind" })[Quickshell.env("CALENDAR_ENTRY")] || "clock")

    Timer { interval: 30000; repeat: true; running: root.state.open; onTriggered: root.now = Date.now() / 1000 }
    Timer { id: unhighlight; interval: 2500; onTriggered: root.highlight = "" }
    // The sync is detached, so Process.running cannot say when it ends. This
    // fallback ends the "syncing…" header, past sync.sh's 120 s lock wait.
    Timer { id: syncGiveUp; interval: 130000; onTriggered: root.syncGaveUp = true }

    // blockAllReads: text() waits for reload(), so a read after a change sees the new file.
    FileView { id: agendaFile; path: root.runtimeDir + "/agenda.json"; blockLoading: true; blockAllReads: true; printErrors: false; watchChanges: true
        onFileChanged: { reload(); root.readAgenda(); root.loadMonth(); root.loadCalendars(); if (root.state.year) root.loadYear(); if (root.state.day) root.loadDay(root.state.day); if (root.state.sheet && root.draft) root.loadDay(root.draft.startDay); } }
    FileView { id: statusFile; path: root.runtimeDir + "/status.json"; blockLoading: true; blockAllReads: true; printErrors: false; watchChanges: true
        onFileChanged: { reload(); root.readStatus(); } }
    FileView { id: draftFile; path: root.runtimeDir + "/draft.json"; blockLoading: true; printErrors: false; atomicWrites: true }
    FileView { id: optionDefault; path: root.configDir + "/options/calendar-default"; blockLoading: true; printErrors: false }
    FileView { id: optionAlert; path: root.configDir + "/options/calendar-alert"; blockLoading: true; printErrors: false }
    FileView { id: optionDuration; path: root.configDir + "/options/calendar-duration"; blockLoading: true; printErrors: false }

    // Detached: a sync must outlive the card; its result arrives through the watched files.
    Process { id: syncer; command: ["bash", "-c", "setsid -f bash \"$1\" </dev/null >/dev/null 2>&1", "bash",
        root.configDir + "/scripts/calendar/sync.sh"] }
    Process { id: settingsLauncher; command: ["setsid", "-f", root.configDir + "/scripts/hyprland/settings-panel.sh", "calendar"] }
    Process {
        id: monthReader
        property string verb: "month"
        property string queued: ""
        onRunningChanged: if (!running && queued) root.startReader(monthReader, queued)
        stdout: StdioCollector { onStreamFinished: root.readerDone(monthReader.verb, text) }
    }
    Process {
        id: yearReader
        property string verb: "year"
        property string queued: ""
        onRunningChanged: if (!running && queued) root.startReader(yearReader, queued)
        stdout: StdioCollector { onStreamFinished: root.readerDone(yearReader.verb, text) }
    }
    Process {
        id: dayReader
        property string verb: "day"
        property string queued: ""
        onRunningChanged: if (!running && queued) root.startReader(dayReader, queued)
        stdout: StdioCollector { onStreamFinished: root.readerDone(dayReader.verb, text) }
    }
    Process {
        id: pickerReader
        property string verb: "month"
        property string queued: ""
        onRunningChanged: if (!running && queued) root.startReader(pickerReader, queued)
        stdout: StdioCollector { onStreamFinished: root.readerDone(pickerReader.verb, text) }
    }
    Process {
        id: peekReader
        property string verb: "day"     // cal.sh's verb; readerDone sees "peek"
        property string queued: ""
        onRunningChanged: if (!running && queued) root.startReader(peekReader, queued)
        stdout: StdioCollector { onStreamFinished: root.readerDone("peek", text) }
    }
    Process {
        id: calendarReader
        command: [root.calSh, "calendars"]
        property bool queued: false
        onRunningChanged: if (!running && queued) root.loadCalendars()
        stdout: StdioCollector { onStreamFinished: {
            let list = null;
            try { list = JSON.parse(text); } catch (e) { list = null; }
            Controller.calendarsReply(Model, root, list);
        } }
    }
    Process {
        id: adder
        property string request: ""
        property string title: ""
        command: [root.calSh, "add"]
        stdinEnabled: true
        // The ICS travels on stdin, never argv. cal.sh reads one line.
        onStarted: { write(request + "\n"); request = ""; }
        property int session: 0
        property string sent: ""
        stdout: StdioCollector { onStreamFinished: {
            let r = null;
            try { r = JSON.parse(text); } catch (e) { r = { ok: false, error: "The calendar helper did not answer." }; }
            Controller.addReply(Model, root, adder.session, adder.sent, adder.title, r, draftFile);
            root.endWrite();
        } }
    }

    Process {
        id: inspector
        property var event: null
        property int session: 0
        stdout: StdioCollector { onStreamFinished: {
            let info = null;
            try { info = JSON.parse(text); } catch (e) { info = null; }
            Controller.inspectReply(Model, root, inspector.session, inspector.event, info);
        } }
    }
    // cal.sh update|delete: one JSON line on stdin, as adder does.
    Process {
        id: updater
        property string request: ""
        property string title: ""
        property int session: 0
        stdinEnabled: true
        onStarted: { write(request + "\n"); stdinEnabled = false; }
        stdout: StdioCollector { onStreamFinished: {
            let r = null;
            try { r = JSON.parse(text); } catch (e) { r = { ok: false, error: "The calendar helper did not answer." }; }
            Controller.updateReply(Model, root, updater.session, updater.title, r);
            root.endWrite();
        } }
        onExited: stdinEnabled = true
    }

    IpcHandler {
        target: "calendar"
        function ping(): string { return "ready"; }
        function toggle(entry: string): void {
            root.act(({ month: "clock", upcoming: "pill", "new": "keybind" })[entry] || "clock");
        }
        function close(): void { root.act("outside"); }
        function status(): string {
            return JSON.stringify({ state: root.state, cardX: card.x, draft: root.draft, header: root.headerStatus(), events: root.agenda.length });
        }
    }

    PanelWindow {
        id: window
        visible: root.state.open || root.closing
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Normal
        WlrLayershell.namespace: "calendar-card"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.state.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        MouseArea { anchors.fill: parent; onClicked: root.act("outside") }

        Card {
            id: card
            controller: root
            focus: true
            enabled: root.state.open
            // Centred: the capsule lives in Waybar's centre group, and a fixed
            // anchor means switching views only changes the card's height.
            x: Math.round((window.width - width) / 2)
            y: root.barAtBottom ? window.height - height - px(8) : px(8)
            onDismissed: if (root.closing) { root.quitting = true; if (!root.writePending) Qt.quit(); }
        }
    }
}
