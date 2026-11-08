pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root
    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    property bool opened: false
    property bool closing: false
    property bool loading: false
    property bool submitting: false
    property bool previewReady: false
    property string problem: ""
    property var snapshot: ({
            entries: [],
            current: "",
            folders: []
        })
    property var entries: []
    property int selectedIndex: 0
    property string query: ""
    property bool searchVisible: false
    property bool reducedMotion: false
    property color background: "#05090c"
    property color foreground: "#cfddde"
    property color accent: "#6097a1"
    readonly property var selected: entries[selectedIndex] || null
    property double openedAt: 0

    function filter() {
        const needle = query.toLocaleLowerCase();
        entries = snapshot.entries.filter(e => e.name.toLocaleLowerCase().includes(needle));
        selectedIndex = 0;
    }
    onQueryChanged: filter()
    function close() {
        closing = true;
        opened = false;
        if (!applyProcess.running)
            Qt.quit();
    }
    function open() {
        if (opened || closing)
            return;
        const focused = Hyprland.focusedMonitor;
        overlay.screen = Quickshell.screens.find(s => focused && s.name === focused.name) || Quickshell.screens[0];
        openedAt = Date.now();
        problem = "";
        query = "";
        searchVisible = false;
        opened = true;
        loading = true;
        stateReader.running = true;
    }
    Component.onCompleted: open()
    function navigate(step) {
        if (!loading && !submitting && entries.length)
            selectedIndex = ((selectedIndex + step) % entries.length + entries.length) % entries.length;   // any step, either way round
    }
    function confirm() {
        if (loading || submitting || !selected)
            return;
        submitting = true;
        problem = "";
        applyProcess.command = [configDir + "/scripts/hyprland/carousel-apply.sh", selected.path];
        applyProcess.running = true;
    }
    IpcHandler {
        target: "carousel"
        function ping(): string {
            return "ready";
        }
        function toggle(): void {
            if (root.closing)
                return;
            if (root.opened)
                root.close();
            else
                root.open();
        }
        function close(): void {
            root.close();
        }
        function status(): string {
            return JSON.stringify({
                opened: root.opened,
                loading: root.loading,
                submitting: root.submitting,
                count: root.entries.length,
                index: root.selectedIndex,
                selected: root.selected?.path || "",
                error: root.problem,
                reducedMotion: root.reducedMotion,
                previewReady: root.previewReady
            });
        }
    }
    Process {
        id: stateReader
        command: [root.configDir + "/scripts/hyprland/carousel-state.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.snapshot = data;
                    root.background = data.background;
                    root.foreground = data.foreground;
                    root.accent = data.accent;
                    root.reducedMotion = data.reducedMotion;
                    root.filter();
                    root.selectedIndex = Math.max(0, root.entries.findIndex(e => e.path === data.current));
                    root.problem = data.error;
                    console.info("Carousel state ready in " + (Date.now() - root.openedAt) + " ms; " + data.entries.length + " images");
                } catch (error) {
                    root.entries = [];
                    root.problem = "Could not read wallpapers. Open Waypaper to check the folder.";
                }
                root.loading = false;
            }
        }
        onExited: code => {
            if (code !== 0) {
                root.loading = false;
                root.problem = "Could not read wallpapers. Check the carousel session log.";
            }
        }
    }
    Process {
        id: applyProcess
        // A collector cannot finish while wall.sh's daemons retain its pipes.
        // The helper/pipeline own detailed stderr and desktop notifications.
        onExited: code => {
            root.submitting = false;
            if (code === 0)
                root.close();
            else if (root.closing)
                Qt.quit();
            else
                root.problem = "Wallpaper could not be fully applied. See the desktop notification; you can retry or close.";
        }
    }
    PanelWindow {
        id: overlay
        visible: root.opened
        color: "transparent"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "wallpaper-carousel"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        Loader {
            anchors.fill: parent
            active: root.opened
            sourceComponent: Carousel {
                controller: root
                pixelScale: overlay.screen?.devicePixelRatio || 1
            }
        }
    }
}
