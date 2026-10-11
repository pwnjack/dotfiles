pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "model.mjs" as Model

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
    property bool closing: false
    property double openedAt: 0
    property bool syncGaveUp: false     // sync.sh waits up to 120 s for its lock; past that, show what we have
    property double now: Date.now() / 1000
    property var agenda: []
    property var status: null
    property var calendars: []
    property var dayEvents: []          // the selected day's (or the sheet's start day's) events
    property string dayFor: ""
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
    function keepDraft() {
        if (Model.keepsDraft(draft)) draftFile.setText(JSON.stringify(draft));
    }
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
        if (restored && !dayKey && minutes === undefined) { draft = restored; return; }
        draft = Model.newDraft(Date.now() / 1000, defaults(), dayKey || null, minutes);
    }
    function newEvent(dayKey, minutes) {        // "+", "New event on …", a timeline gap
        state = Model.openSheet(state);
        startSheet(dayKey, minutes);
    }
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
        else if (key === state.day) { dayEvents = asArray(parseJson(body)); dayFor = key; }   // a day the card no longer shows is dropped
    }
    // The helpers print {"ok":false,"error":…} on failure: any other shape reads as empty.
    function parseJson(body) { try { return JSON.parse(body); } catch (e) { return null; } }
    function parseBusy(body) { const r = parseJson(body); return r && Array.isArray(r.busy) ? r.busy : []; }
    function parseCounts(body) { const r = parseJson(body); return r && Array.isArray(r.counts) && r.counts.length === 12 ? r.counts : []; }
    function loadMonth() {
        startReader(monthReader, viewYear + "-" + String(viewMonth + 1).padStart(2, "0"));
    }
    function loadYear() { startReader(yearReader, String(viewYear)); }
    function loadDay(key) { if (key) startReader(dayReader, key); }
    function loadCalendars() { calendarReader.running = true; }
    function shiftMonth(delta) {
        const d = new Date(viewYear, viewMonth + delta, 1);
        viewYear = d.getFullYear(); viewMonth = d.getMonth();
        loadMonth();
    }
    function shiftYear(delta) { viewYear += delta; loadYear(); }
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
    function cancelSheet() { draftFile.setText(""); draft = null; act("esc"); }
    function add() {
        if (!draft || !Model.validate(draft).ok || adder.running) return;
        addError = "";
        const nowS = Math.floor(Date.now() / 1000);
        adder.request = JSON.stringify({ calendar: draft.calendar, ics: Model.buildIcs(draft, nowS, Model.newUid(nowS)) });
        adder.title = draft.title.trim();
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
        onFileChanged: { reload(); root.readAgenda(); root.loadMonth(); if (root.state.day) root.loadDay(root.state.day); } }
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
        id: calendarReader
        command: [root.calSh, "calendars"]
        stdout: StdioCollector { onStreamFinished: {
            try { root.calendars = root.asArray(JSON.parse(text)); } catch (e) { root.calendars = []; }
            // A sheet opened before this read landed has no calendar yet: take the default now.
            if (root.draft && root.draft.mode !== "edit" && !root.draft.calendar)
                root.draft = Object.assign({}, root.draft, { calendar: root.defaults().calendar });
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
        stdout: StdioCollector { onStreamFinished: {
            let r = null;
            try { r = JSON.parse(text); } catch (e) { r = { ok: false, error: "The calendar helper did not answer." }; }
            if (r.ok) {
                draftFile.setText("");
                root.draft = null;
                root.highlight = adder.title;
                unhighlight.restart();
                root.act("esc");
            } else root.addError = r.error || "The event could not be saved.";
        } }
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
            onDismissed: if (root.closing) Qt.quit()
        }
    }
}
