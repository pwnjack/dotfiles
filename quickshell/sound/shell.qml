pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import "model.mjs" as Model

// The sound popover for Waybar's volume icon. Started by
// scripts/hyprland/sound-popover.sh; the process exits on close, so the pins
// watch, the battery timer and the mic meter run only while it is open. It is
// the controller of Popover.qml (the contract is in Popover's header): live
// state comes from PipewireAdapter, every decision from model.mjs.
ShellRoot {
    id: root
    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    readonly property color background: Quickshell.env("SOUND_BACKGROUND") || "#05090c"
    readonly property color foreground: Quickshell.env("SOUND_FOREGROUND") || "#cfddde"
    readonly property color accent: Quickshell.env("SOUND_ACCENT") || "#6097a1"
    // Text on the accent. Not "onAccent": QML reads an on<Name> property as
    // the handler of <name>'s change signal.
    readonly property color accentInk: Quickshell.env("SOUND_ON_ACCENT") || "#05090c"
    readonly property string monoFont: Quickshell.env("SOUND_FONT") || "monospace"
    readonly property real cursorX: Number(Quickshell.env("SOUND_CURSOR_X") || "-1")
    readonly property bool barAtBottom: Quickshell.env("SOUND_BAR_POSITION") === "bottom"
    // A popover belongs to the bar, so it keeps the bar's own pixel sizes.
    readonly property real uiScale: 1

    property bool opened: false
    property bool closing: false
    property string tab: "devices"      // devices | apps
    property string picker: ""          // "" | output | input

    // The pins map (stream object id -> target object.serial) from the latest
    // line of `sound.sh pins --watch`; pinsKnown is false until its first line
    // and again once it fails.
    property var pins: ({})
    property bool pinsKnown: false
    property bool pinsFailed: false
    property var headsets: []
    property var hidden: []
    property var names: ({})
    // App key -> route request in flight; `pending` is its view for model.mjs.
    property var requests: ({})
    property var pending: ({})
    property string routeError: ""

    readonly property bool ready: adapter.ready
    readonly property var classes: Model.classify(adapter.nodes)
    readonly property var battery: Model.batteryFor(adapter.nodes, headsets)
    readonly property var outputs: Model.deviceList("output", classes,
        { hidden: hidden, names: names, battery: battery, defaultId: adapter.defaultSink })
    readonly property var inputs: Model.deviceList("input", classes,
        { hidden: hidden, names: names, battery: battery, defaultId: adapter.defaultSource })
    readonly property var output: currentOf(outputs)
    readonly property var input: currentOf(inputs)
    readonly property var apps: Model.appList(classes, { names: names, pins: pins, pending: pending })
    readonly property var targets: Model.routeTargets(classes, { names: names, hidden: hidden, defaultId: adapter.defaultSink })
    readonly property string status: routeError || (pinsFailed ? "Routes cannot be read" : "")
    readonly property real meter: peakMonitor.peak

    function currentOf(list) {
        for (let i = 0; i < list.shown.length; i++) if (list.shown[i].current) return list.shown[i];
        return null;
    }
    // A device is keyed by node.name, a stream by its object.serial: object
    // ids are reused, so a key can never reach a stream that replaced the one
    // it named. The object id is used only for the adapter's node lookup.
    function nodeFor(key) {
        const nodes = adapter.nodes;
        for (let i = 0; i < nodes.length; i++) {
            const node = nodes[i];
            if (!node.isStream && node.name === key) return node;
        }
        return Model.streamBySerial(nodes, key);
    }

    function open() {
        if (opened) return;
        tab = "devices";
        picker = "";
        // A reopen during the close fade cancels the close.
        // opened before closing, and closing before opened in close(): the
        // window's visible binding re-evaluates after each assignment, and a
        // moment with both false unmaps the layer (a blink).
        if (closing) {
            opened = true;
            closing = false;
            popover.appear();
            return;
        }
        const focused = Hyprland.focusedMonitor;
        window.screen = Quickshell.screens.find(s => focused && s.name === focused.name) || Quickshell.screens[0];
        opened = true;
        devicesReader.running = true;
        popover.appear();
    }
    function close() {
        if (closing) return;
        closing = true;
        opened = false;
        popover.disappear();
    }
    Component.onCompleted: open()

    function setTab(t) { tab = t; }
    function openPicker(kind) { picker = kind; }
    function closePicker() { picker = ""; }
    function choose(kind, key) {
        const node = nodeFor(key);
        if (node) adapter.setDefault(kind, node.id);
        closePicker();
    }
    function setVolume(key, value) {
        const node = nodeFor(key);
        if (node) adapter.setVolume(node.id, value);
    }
    function setMuted(key, muted) {
        const node = nodeFor(key);
        if (node) adapter.setMuted(node.id, muted);
    }
    function openSettings() {
        launcher.command = ["bash", "-c", "setsid -f bash \"$1\" sound </dev/null >/dev/null 2>&1", "bash",
            configDir + "/scripts/hyprland/settings-panel.sh"];
        launcher.running = true;
    }
    function openAdvanced() {
        launcher.command = ["bash", "-c", "setsid -f pavucontrol </dev/null >/dev/null 2>&1"];
        launcher.running = true;
    }

    // route(appKey, targetName | "default"): the helper's exit 0 means only
    // that PipeWire took the request, so the row stays pending until the
    // stream links into the target, for at most 2 s.
    function route(appKey, target) {
        const app = apps.find(a => a.key === appKey);
        if (!app) return;
        const sink = targets.find(t => t.name === target);
        const request = routeRequest.createObject(root, {
            key: appKey, target: target, app: app.name,
            label: target === "default" ? "Default" : sink ? sink.label
                : target === app.route.target ? app.route.label : target,
        });
        request.command = ["bash", configDir + "/scripts/sound/sound.sh", "route", String(app.serial), target];
        const next = Object.assign({}, requests);
        next[appKey] = request;
        requests = next;
        syncPending();
        request.running = true;
    }
    function syncPending() {
        const view = {};
        for (const key in requests) view[key] = requests[key].target;
        pending = view;
    }
    // Did the stream reach the request's target? The key is the stream's
    // serial, so a stream that took the ended one's object id never counts.
    function reached(request) {
        return Model.routeReached(adapter.nodes, request.key, request.target, adapter.defaultSink);
    }
    // Retire a request: done, or failed with the status line. A request a
    // newer one for the same app replaced only goes away.
    function finish(request, ok) {
        if (requests[request.key] === request) {
            const next = Object.assign({}, requests);
            delete next[request.key];
            requests = next;
            syncPending();
            if (!ok) {
                routeError = "Could not move " + request.app + " to " + request.label;
                errorTimer.restart();
            }
        }
        request.destroy();
    }
    function settle() {
        for (const key in requests) {
            const request = requests[key];
            if (request.accepted && reached(request)) request.retire(true);
        }
    }

    PipewireAdapter {
        id: adapter
        onNodesChanged: root.settle()
    }

    Component {
        id: routeRequest
        Process {
            id: request
            property string key
            property string target
            property string app
            property string label
            property bool accepted: false
            property bool retired: false
            function retire(ok) {
                if (retired) return;
                retired = true;
                deadline.stop();
                root.finish(request, ok);
            }
            onExited: code => {
                if (code !== 0) retire(false);
                else {
                    accepted = true;
                    if (root.reached(request)) retire(true);
                }
            }
            property Timer deadline: Timer {
                interval: 2000
                running: true
                onTriggered: request.retire(request.accepted && root.reached(request))
            }
        }
    }
    Timer {
        id: errorTimer
        interval: 4000
        onTriggered: root.routeError = ""
    }

    // Lives only while open; any line is the whole map (the latest wins). A
    // failure prints {"ok":false,…} and exits, which leaves routes unknown.
    Process {
        id: pinsWatch
        command: ["bash", root.configDir + "/scripts/sound/sound.sh", "pins", "--watch"]
        running: root.opened
        stdout: SplitParser {
            onRead: line => {
                let map = null;
                try {
                    map = JSON.parse(line);
                } catch (error) {
                    return;
                }
                if (!map || typeof map !== "object" || map.ok === false) return;
                root.pins = map;
                root.pinsKnown = true;
                root.pinsFailed = false;
            }
        }
        onExited: {
            if (!root.opened) return;
            root.pins = {};
            root.pinsKnown = false;
            root.pinsFailed = true;
        }
    }

    // The headset battery: devices.sh on open, then every 60 s while open.
    Process {
        id: devicesReader
        command: ["bash", root.configDir + "/scripts/devices/devices.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const rows = JSON.parse(text);
                    root.headsets = Array.isArray(rows) ? rows.filter(row => row && row.kind === "headset") : [];
                } catch (error) {
                    root.headsets = [];
                }
            }
        }
        onExited: code => { if (code !== 0) root.headsets = []; }
    }
    Timer {
        interval: 60000
        repeat: true
        running: root.opened
        onTriggered: devicesReader.running = true
    }

    // Settings writes these; watched, so a rename shows at once.
    FileView {
        path: root.configDir + "/options/sound-hidden"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.hidden = Model.parseHidden(text())
        onLoadFailed: root.hidden = []
    }
    FileView {
        path: root.configDir + "/options/sound-names"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.names = Model.parseNames(text())
        onLoadFailed: root.names = {}
    }

    PwNodePeakMonitor {
        id: peakMonitor
        node: Pipewire.defaultAudioSource
        enabled: popover.meterActive && root.opened
    }

    // Detached with stdio closed: a child left on this process's pipes dies
    // of SIGPIPE once the popover has exited.
    Process { id: launcher; onExited: root.close() }

    IpcHandler {
        target: "sound"
        function ping(): string { return "ready"; }
        function toggle(): void { if (root.opened) root.close(); else root.open(); }
        function close(): void { root.close(); }
        function status(): string {
            return JSON.stringify({
                opened: root.opened, tab: root.tab, picker: root.picker, apps: root.apps.length,
                output: root.output ? root.output.name : null,
                input: root.input ? root.input.name : null
            });
        }
    }

    PanelWindow {
        id: window
        visible: root.opened || root.closing
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        // Normal: respect Waybar's exclusive zone, so the window starts just
        // below (or above) the bar and the popover sits a gap away from it.
        exclusionMode: ExclusionMode.Normal
        WlrLayershell.namespace: "sound-popover"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        MouseArea { anchors.fill: parent; onClicked: root.close() }

        Popover {
            id: popover
            controller: root
            focus: true
            enabled: root.opened
            visible: root.opened || root.closing
            readonly property int edge: px(12)
            readonly property real anchorX: root.cursorX >= 0 ? root.cursorX - (window.screen ? window.screen.x : 0) : window.width
            x: Math.max(edge, Math.min(window.width - width - edge, anchorX - width / 2))
            y: root.barAtBottom ? window.height - height - px(8) : px(8)
            fromBottom: root.barAtBottom
            originX: anchorX - x
            onDismissed: if (root.closing) Qt.quit()
        }
    }
}
