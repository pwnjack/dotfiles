pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "deviceRead.mjs" as DeviceRead
import "calendar.mjs" as CalendarRead

ShellRoot {
    id: root
    readonly property string configDir: Quickshell.env("HOME") + "/.config"
    property bool opened: true
    property bool closing: false
    property bool busy: false
    property bool authPending: false
    // Set when an authorised write timed out with its polkit dialog possibly still open.
    property bool authStalled: false
    // Probed (docs/settings-panel.md): hyprpolkitagent's dialog is hidden behind this Overlay surface.
    readonly property bool authHidesPanel: true
    property bool loading: true
    property bool loaded: false
    property string problem: ""
    property var catalog: ({ categories: [], rows: [] })
    property string category: "appearance"
    property string query: ""
    property var values: ({})
    property var monitors: []
    property var network: null
    property var startup: null
    property var about: null
    // Devices page: devices.sh every 10 s while the page is on screen; nothing otherwise.
    property var devices: null
    // Calendar page: calendarStatus every 5 s while the page is on screen; nothing otherwise.
    property var calendar: null
    // Sound page: soundDevices on show, after a write, and on the audio events while the page is on screen.
    property var sound: null
    // The last failed soundDevices read, shown on the Sound page with a Retry; cleared by the next good read.
    property string soundError: ""
    readonly property bool soundShown: opened && !closing && category === "sound" && !query.trim()
    readonly property bool calendarShown: opened && !closing && category === "calendar" && !query.trim()
    readonly property bool devicesShown: opened && !closing && category === "devices" && !query.trim()
    // Bumped when the page is hidden, so a read still in flight cannot land afterwards.
    // Only on hide: the Timer's first read on show may fire before this handler, and a
    // bump there would discard it and leave "Reading devices…" up for a full interval.
    property int deviceGeneration: 0
    onDevicesShownChanged: if (!devicesShown) { deviceGeneration++; deviceReader.running = false; }
    readonly property string initialPage: Quickshell.env("SETTINGS_PAGE") || ""
    property string mainMonitor: ""
    property var pendingDisplay: null
    property var stagedDisplays: ({})
    property bool displaysSkipped: false
    // A network snapshot that arrived while a password was being typed was held
    // back so the list stayed still; replay it once the field closes.
    property bool networkSkipped: false
    // Whether the full read in flight asked for the network view.
    property bool readerNetwork: false
    property bool readerStartup: false
    property bool readerAboutFull: false
    onInteractingChanged: {
        if (interacting !== "network.psk" && networkSkipped) {
            networkSkipped = false;
            liveDirty = Object.assign({}, liveDirty, {network: true});
            liveTimer.restart();
        }
        if (interacting.startsWith("display:") || !displaysSkipped) return;
        displaysSkipped = false;
        markLive("displays");
    }
    property string interacting: ""
    property var liveDirty: ({})
    property string liveReply: ""
    property int liveReads: 0
    // Only what is on screen is watched: no page, no subscription. A row marked
    // inView (the network.wifi toggle, drawn by NetworkView itself) contributes
    // no live tag on its own — otherwise a search that merely matches its title
    // would start the network poller even while looking at an unrelated page.
    readonly property var liveTags: {
        const tags = new Set(visibleRows.filter(row => !row.inView).map(row => row.live).filter(Boolean));
        if (category === "monitors" && !query.trim()) tags.add("displays");
        if (category === "network" && !query.trim()) tags.add("network");
        return [...tags];
    }
    property var shownTags: []
    onLiveTagsChanged: {
        const previous = shownTags;
        const added = liveTags.filter(tag => !previous.includes(tag));
        const removed = previous.filter(tag => !liveTags.includes(tag));
        shownTags = liveTags;
        // Before the first full read (loaded false) that read already asks for the
        // network view. A full read already in flight may not (it was started on
        // another page), so the live read is deferred behind it, never dropped.
        // A full read in flight that already asks for the network view makes a live
        // read redundant; one started on another page does not, so the live read is
        // deferred behind it. Before any read has started, refresh() is about to run
        // with the network flag set.
        if (added.includes("network") && opened && !busy && (reader.running || loaded) && !(reader.running && readerNetwork)) {
            liveDirty = Object.assign({}, liveDirty, {network: true});
            if (reader.running) liveTimer.restart();
            else readLive();
        }
        if (removed.includes("network")) { scanner.running = false; scanSettle.stop(); }
    }
    // Covers the third way the network tag "goes away": closing the panel while
    // still on the network page, which changes no category/query and so never
    // fires onLiveTagsChanged above.
    onOpenedChanged: { if (!opened) { scanner.running = false; scanSettle.stop(); } }
    property var queue: []
    property string readReply: ""
    property string writeReply: ""
    property string writeRequest: ""
    property string readError: ""
    property string writeError: ""
    readonly property double startedAt: Number(Quickshell.env("SETTINGS_STARTED_MS")) || Date.now()
    property int frameMs: -1
    property int readyMs: -1
    readonly property color background: Quickshell.env("SETTINGS_BACKGROUND") || "#0e1416"
    readonly property color foreground: Quickshell.env("SETTINGS_FOREGROUND") || "#dee3e5"
    readonly property color accent: Quickshell.env("SETTINGS_ACCENT") || "#82d3e1"
    readonly property color accentText: Quickshell.env("SETTINGS_ON_ACCENT") || "#00363d"
    readonly property color errorColor: Quickshell.env("SETTINGS_ERROR") || "#ffb4ab"
    readonly property var visibleRows: {
        const words = query.toLocaleLowerCase().trim().split(/\s+/).filter(Boolean);
        return catalog.rows.filter(row => {
            if (!words.length) return row.category === category && !row.inView;
            const page = catalog.categories.find(c => c.id === row.category);
            // Section titles count too: "night light" or "output" names a group, not each row in it.
            const section = (page?.sections || []).find(s => s.id === row.section)?.title || "";
            const hay = [row.title, row.description, page?.title || "", section].concat(row.keywords || []).join(" ").toLocaleLowerCase();
            return words.every(word => hay.includes(word));
        });
    }
    function refresh() {
        if (!opened || busy || !catalog.rows.length) return;
        if (reader.running) return;
        // One small value snapshot per opening/edit. Tabs only rebuild widgets;
        // they never start a helper or briefly display unchecked/default values.
        const ids = catalog.rows.map(row => row.id);
        readReply = "";
        readError = "";
        loading = true;
        readerNetwork = category === "network";
        readerStartup = category === "startup";
        readerAboutFull = category === "about";
        reader.command = ["bash", configDir + "/scripts/settings/panel-request.sh", JSON.stringify({op: "read", ids: ids, monitors: true, network: category === "network", startup: category === "startup", about: readerAboutFull ? "full" : "summary"})];
        reader.running = true;
        // A full read supersedes any live read still waiting on its debounce.
        liveDirty = ({});
        liveTimer.stop();
    }
    function markLive(tag) {
        // A write refreshes everything afterwards, so its own echoes are not news.
        if (busy || reader.running || !liveTags.includes(tag)) return;
        liveDirty = Object.assign({}, liveDirty, {[tag]: true});
        liveTimer.restart();
    }
    function readLive() {
        const tags = Object.keys(liveDirty).filter(tag => liveTags.includes(tag));
        if (!tags.length || busy || closing) { liveDirty = ({}); return; }
        if (reader.running || liveReader.running) { liveTimer.restart(); return; }
        liveDirty = ({});
        liveReads += 1;
        const ids = catalog.rows.filter(row => tags.includes(row.live)).map(row => row.id);
        liveReply = "";
        liveReader.command = ["bash", configDir + "/scripts/settings/panel-request.sh", JSON.stringify({op: "read", ids: ids, monitors: tags.includes("displays"), network: tags.includes("network")})];
        liveReader.running = true;
    }
    function select(id) {
        query = ""; category = id;
        // The startup list is read on every visit (files change behind the panel's back);
        // network data only when it is missing. Both are read again after every edit.
        // refresh() already ignores the call while a read runs; onExited catches up.
        if (id === "startup" || (id === "network" && !network) || (id === "about" && (!about || about.session === undefined))) refresh();
    }
    function change(id, value) {
        submit({op: "set", id: id, value: value}, catalog.rows.find(row => row.id === id)?.auth === true);
    }
    function reset(id) { submit({op: "reset", id: id}); }
    function action(id) { submit({op: "action", id: id}); }
    function keepDisplay() { submit({op: "displayKeep"}); }
    function revertDisplay() {
        // Cleared first so the countdown cannot submit twice; the next read restores it if still pending.
        pendingDisplay = null;
        submit({op: "displayRevert"});
    }
    function submit(request, auth) {
        if (closing) return;
        problem = "";
        queue = queue.concat([{request: request, auth: auth === true}]);
        busy = true;
        drain();
    }
    function drain() {
        if (writer.running || reader.running || liveReader.running) return;
        if (!queue.length) {
            busy = false;
            if (closing) Qt.quit();
            else { refresh(); readSound(); }
            return;
        }
        busy = true;
        const queued = queue[0];
        const request = queued.request;
        queue = queue.slice(1);
        authPending = queued.auth;
        writeReply = "";
        writeError = "";
        writeRequest = JSON.stringify(request);
        writer.command = ["bash", configDir + "/scripts/settings/panel-request.sh", "-"];
        writer.running = true;
    }
    function close() {
        // A layout nobody confirmed is never left behind.
        if (pendingDisplay && !closing) revertDisplay();
        closing = true;
        opened = false;
        if (!writer.running && !queue.length) Qt.quit();
    }
    FileView {
        preload: true
        path: root.configDir + "/quickshell/settings-panel/catalog.json"
        onLoaded: {
            try {
                root.catalog = JSON.parse(text());
                if (root.catalog.categories.some(c => c.id === root.initialPage)) root.category = root.initialPage;
                root.refresh();
            }
            catch (error) { root.problem = "Could not load settings: " + error; root.loading = false; }
        }
        onLoadFailed: { root.problem = "Could not read the settings catalog."; root.loading = false; }
    }
    IpcHandler {
        target: "settings"
        function toggle(): void {
            // Back after a timed-out prompt: the dialog may have applied the change since.
            if (root.authStalled) { root.authStalled = false; root.refresh(); return; }
            if (root.opened) root.close();
            else { root.closing = false; root.opened = true; }
        }
        function close(): void { root.close(); }
        // Not `show`: qs parses that word as its own `ipc show` subcommand even inside `ipc call`.
        function page(category: string): void { root.select(category); }
        function open(category: string): void {
            const stalled = root.authStalled;
            root.authStalled = false;
            root.closing = false; root.opened = true;
            if (stalled) root.refresh();
            if (root.catalog.categories.some(c => c.id === category)) root.select(category);
        }
        function status(): string {
            return JSON.stringify({opened: root.opened, loading: root.loading, busy: root.busy,
                category: root.category, rows: root.visibleRows.length, error: root.problem,
                frameMs: root.frameMs, readyMs: root.readyMs,
                liveTags: root.liveTags, liveReads: root.liveReads,
                network: root.network ? (root.network.running ? "up" : "down") : "none",
                rowErrors: root.visibleRows.filter(row => root.values[row.id]?.error).map(row => ({id:row.id,error:root.values[row.id].error}))});
        }
    }
    Process {
        id: deviceReader
        command: ["bash", root.configDir + "/scripts/devices/devices.sh"]
        property int generation: -1
        stdout: StdioCollector {
            onStreamFinished: if (DeviceRead.fresh(deviceReader.generation, root.deviceGeneration, root.devicesShown)) root.devices = DeviceRead.parse(text)
        }
        // A hide/show faster than one read finds the killed run still "running", so the
        // Timer's read on show was skipped; start it now that the stale run has gone.
        onExited: if (root.devicesShown && generation !== root.deviceGeneration) { generation = root.deviceGeneration; running = true }
    }
    Timer {
        interval: 10000; repeat: true; triggeredOnStart: true
        running: root.devicesShown
        onTriggered: if (!deviceReader.running) { deviceReader.generation = root.deviceGeneration; deviceReader.running = true }
    }
    // Bumped when the page is hidden, so a read still in flight cannot land afterwards (as the Devices page does).
    property int calendarGeneration: 0
    onCalendarShownChanged: if (!calendarShown) { calendarGeneration++; calendarReader.running = false; }
    // The read failure currently shown in `problem`; cleared by the next good read, never a write's error.
    property string calendarError: ""
    Process {
        id: calendarReader
        command: ["bash", root.configDir + "/scripts/settings/panel-request.sh", JSON.stringify({op: "calendarStatus"})]
        property int generation: -1
        property string reply: ""
        property string errorText: ""
        stdout: StdioCollector { onStreamFinished: calendarReader.reply = text }
        stderr: StdioCollector { onStreamFinished: calendarReader.errorText = text }
        onExited: code => {
            if (CalendarRead.fresh(generation, root.calendarGeneration, root.calendarShown)) {
                const result = CalendarRead.readReply(calendarReader.reply, calendarReader.errorText, code);
                // A failed read keeps the model already shown; the banner says it is out of date.
                // The banner is shared with write errors, so the helper decides who owns it.
                if (result.calendar) root.calendar = result.calendar;
                const next = CalendarRead.nextProblem(root.problem, root.calendarError, result.calendar ? "" : "Could not read calendars: " + result.error);
                root.problem = next.problem;
                root.calendarError = next.shownRead;
            }
            calendarReader.reply = "";
            calendarReader.errorText = "";
            // A hide/show faster than one read finds the killed run still "running": start the read the Timer skipped.
            if (root.calendarShown && generation !== root.calendarGeneration) { generation = root.calendarGeneration; running = true }
        }
    }
    Timer {
        interval: 5000; repeat: true; triggeredOnStart: true
        running: root.calendarShown
        onTriggered: if (!calendarReader.running) { calendarReader.generation = root.calendarGeneration; calendarReader.running = true }
    }
    // Bumped when the page is hidden, so a read still in flight cannot land afterwards (Calendar's rule).
    property int soundGeneration: 0
    onSoundShownChanged: {
        if (soundShown) readSound();
        else { soundGeneration++; soundReader.running = false; soundTimer.stop(); }
    }
    function readSound() {
        // A write in flight reads again when it drains, so a read now would show the state before it.
        if (!soundShown || busy) return;
        if (soundReader.running) { soundTimer.restart(); return; }
        soundReader.generation = soundGeneration;
        soundReader.running = true;
    }
    Process {
        id: soundReader
        command: ["bash", root.configDir + "/scripts/settings/panel-request.sh", JSON.stringify({op: "soundDevices"})]
        property int generation: -1
        property string reply: ""
        property string errorText: ""
        stdout: StdioCollector { onStreamFinished: soundReader.reply = text }
        stderr: StdioCollector { onStreamFinished: soundReader.errorText = text }
        onExited: code => {
            if (CalendarRead.fresh(generation, root.soundGeneration, root.soundShown)) {
                // A failed read keeps the devices already shown; soundError says the list may be out of date.
                let result = null;
                try { result = JSON.parse(soundReader.reply); } catch (_) { /* No reply: the helper failed before answering. */ }
                if (code === 0 && result && result.ok && result.sound) {
                    root.sound = result.sound;
                    root.soundError = "";
                } else {
                    const detail = String(soundReader.errorText || "").trim().split("\n").pop();
                    root.soundError = "Could not read audio devices: " + ((result && result.error) || detail || "the settings helper exited " + code + " without a usable reply");
                }
            }
            soundReader.reply = "";
            soundReader.errorText = "";
        }
    }
    function retrySound() { readSound(); }
    // Audio events come in bursts (a profile switch is several): one read after they settle.
    Timer { id: soundTimer; interval: 300; onTriggered: root.readSound() }
    // Calendar writes take the same queue as every other change: the password goes on stdin, and a failure lands in `problem`.
    function calendarRequest(request) { submit(request); }
    // Sound writes (a device's name or visibility) take the same queue; a failure lands in `problem`.
    function soundRequest(request) { submit(request); }
    Process {
        id: reader
        stdout: StdioCollector { onStreamFinished: root.readReply = text }
        stderr: StdioCollector { onStreamFinished: root.readError = text }
        onExited: code => {
            try {
                const result = JSON.parse(root.readReply);
                if (!result.ok) throw new Error(result.error);
                root.values = Object.assign({}, root.values, result.values);
                // A password mid-edit keeps its own network snapshot: replacing it here
                // would recreate the Wi-Fi list's delegates under the user's hands.
                if (result.network) { if (root.interacting !== "network.psk") root.network = result.network; else root.networkSkipped = true; }
                if (result.startup) root.startup = result.startup;
                if (result.about) root.about = root.readerAboutFull ? result.about : Object.assign({}, root.about || {}, result.about);
                // An open display dropdown keeps its card (the read is replayed when it
                // closes); a queued Keep/Revert is about to change pendingDisplay.
                if (result.monitors && root.interacting.startsWith("display:")) root.displaysSkipped = true;
                else if (result.monitors) { root.monitors = result.monitors; root.mainMonitor = result.mainMonitor; if (!root.busy) root.pendingDisplay = result.displayPending; }
                root.readyMs = Date.now() - root.startedAt;
                console.info("Settings ready in " + root.readyMs + " ms");
            } catch (error) { root.problem = root.readError.trim() || "Could not read settings: " + error; }
            root.loading = false;
            root.loaded = true;
            if (root.queue.length || root.closing) root.drain();
            // The page was opened while this read was in flight and did not ask for its data.
            else if (((root.category === "startup" && !root.readerStartup) || (root.category === "about" && (!root.about || root.about.session === undefined))) && !root.problem) root.refresh();
        }
    }
    Process {
        id: writer
        stdinEnabled: true
        // The request travels on stdin, never argv: it may carry a Wi-Fi password.
        onStarted: { writer.write(root.writeRequest + "\n"); root.writeRequest = ""; }
        stdout: StdioCollector { onStreamFinished: root.writeReply = text }
        stderr: StdioCollector { onStreamFinished: root.writeError = text }
        onExited: code => {
            const wasAuth = root.authPending;
            root.authPending = false;
            root.writeRequest = "";
            try {
                const result = JSON.parse(root.writeReply);
                if (code !== 0 || !result.ok) throw new Error(result.error || "Settings helper failed");
                if (result.pending !== undefined) root.pendingDisplay = result.pending;
                // Closed while this Apply was in flight: close() saw no pending change
                // yet, and submit() ignores requests once closing, so queue it directly.
                if (root.closing && result.pending) { root.pendingDisplay = null; root.queue = root.queue.concat([{request: {op: "displayRevert"}, auth: false}]); }
            } catch (error) {
                root.problem = String(error);
                if (!root.writeReply.trim()) root.problem = root.writeError.trim() || "The settings helper stopped before confirming the change.";
                // The polkit dialog outlives a timed-out call: stay out of its way (hidden,
                // no keyboard grab) until the user opens the panel again.
                if (wasAuth && root.problem.includes("Authentication timed out")) root.authStalled = true;
                root.queue = [];
                root.closing = false;
                root.opened = true;
            }
            root.drain();
        }
    }
    Timer { id: liveTimer; interval: 300; onTriggered: root.readLive() }
    Process {
        id: audioEvents
        running: root.opened && root.liveTags.includes("audio")
        command: ["pactl", "subscribe"]
        // `sink-input #3` must not count as `sink`; clients and streams are noise.
        stdout: SplitParser { onRead: line => {
            if (!/ on (sink|source|card|server)( #|$)/.test(line)) return;
            root.markLive("audio");
            if (root.soundShown) soundTimer.restart();
        } }
    }
    Process {
        id: networkEvents
        running: root.opened && root.liveTags.includes("network")
        command: ["nmcli", "monitor"]
        stdout: SplitParser { onRead: _line => root.markLive("network") }
    }
    // Scans only while the page is on screen; NM's own background scanning is untouched.
    Timer {
        interval: 20000; repeat: true; triggeredOnStart: true
        running: root.opened && root.liveTags.includes("network")
        onTriggered: { if (!root.busy && !scanner.running) scanner.running = true; }
    }
    Process {
        id: scanner
        command: ["bash", root.configDir + "/scripts/settings/panel-request.sh", JSON.stringify({op: "networkScan"})]
        // Only restarts the settle timer if the panel is open and the page (or a
        // matching search) is still up; otherwise a scan that outlives either would relight it.
        onExited: { if (root.opened && root.liveTags.includes("network")) scanSettle.restart(); }
    }
    // A scan completes a few seconds later, and `nmcli monitor` may not report it (docs/settings-panel.md).
    Timer { id: scanSettle; interval: 5000; onTriggered: root.markLive("network") }
    Connections {
        target: Hyprland
        enabled: root.opened && root.liveTags.includes("displays")
        function onRawEvent(event) {
            if (["monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2", "configreloaded"].includes(event.name)) root.markLive("displays");
        }
    }
    Process {
        id: liveReader
        stdout: StdioCollector { onStreamFinished: root.liveReply = text }
        onExited: code => {
            try {
                const result = JSON.parse(root.liveReply);
                if (!result.ok) throw new Error(result.error);
                const values = Object.assign({}, result.values);
                // Never move a control under the user's hand.
                delete values[root.interacting];
                root.values = Object.assign({}, root.values, values);
                if (result.network) { if (root.interacting !== "network.psk") root.network = result.network; else root.networkSkipped = true; }
                // An open display dropdown keeps its card (the read is replayed when it
                // closes); a queued Keep/Revert is about to change pendingDisplay.
                if (result.monitors && root.interacting.startsWith("display:")) root.displaysSkipped = true;
                else if (result.monitors) { root.monitors = result.monitors; root.mainMonitor = result.mainMonitor; if (!root.busy) root.pendingDisplay = result.displayPending; }
            } catch (error) { console.warn("Live refresh failed: " + error); }
            if (Object.keys(root.liveDirty).length) liveTimer.restart();
            if (root.busy || root.closing) root.drain();
        }
    }
    PanelWindow {
        id: overlay
        visible: root.opened && !((root.authPending || root.authStalled) && root.authHidesPanel)
        color: "transparent"
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) || Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "settings-panel"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened && !root.authPending && !root.authStalled ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        SettingsView {
            anchors.fill: parent
            controller: root
            onFramePresented: {
                root.frameMs = Date.now() - root.startedAt;
                console.info("Settings first frame in " + root.frameMs + " ms");
            }
        }
        Component.onCompleted: console.info("Settings window created in " + (Date.now() - Number(Quickshell.env("SETTINGS_STARTED_MS"))) + " ms")
    }
}
