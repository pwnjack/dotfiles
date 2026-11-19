pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "model.mjs" as Model

// The weather card for Waybar's custom/weather. Started by
// scripts/hyprland/weather-popover.sh; the process exits on close. It opens on
// the forecast scripts/weather/forecast.sh saved last, and asks for a new one
// only when that copy is older than Model.FRESH_SECONDS.
ShellRoot {
    id: root
    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    readonly property color background: Quickshell.env("WEATHER_BACKGROUND") || "#05090c"
    readonly property color foreground: Quickshell.env("WEATHER_FOREGROUND") || "#cfddde"
    readonly property color accent: Quickshell.env("WEATHER_ACCENT") || "#6097a1"
    readonly property string monoFont: Quickshell.env("WEATHER_FONT") || "monospace"
    readonly property real cursorX: Number(Quickshell.env("WEATHER_CURSOR_X") || "-1")
    readonly property bool barAtBottom: Quickshell.env("WEATHER_BAR_POSITION") === "bottom"
    readonly property string clockMode: Quickshell.env("WEATHER_CLOCK") === "12h" ? "12h" : "24h"
    readonly property var locale: Qt.locale(Quickshell.env("WEATHER_LOCALE") || "en_US")
    // A popover belongs to the bar, so it keeps the bar's own pixel sizes
    // instead of scaling with the output, as the update card does.
    readonly property real uiScale: 1

    property bool opened: false
    property bool closing: false
    property var forecast: null
    property string phase: "updating"   // updating | ready | failed (Model.view)
    property string reason: ""
    property double clock: Date.now() / 1000   // epoch s, for "Updated 4 min ago"

    function parse(text) {
        try {
            const parsed = JSON.parse(text);
            return parsed && parsed.daily && parsed.hourly ? parsed : null;
        } catch (error) {
            return null;
        }
    }

    function open() {
        if (opened || saved.running) return;
        // A reopen during the close fade cancels the close.
        // opened before closing, and closing before opened in close(): the
        // window's visible binding re-evaluates after each assignment, and a
        // moment with both false unmaps the layer (a blink).
        if (closing) {
            opened = true;
            closing = false;
            card.appear();
            return;
        }
        const focused = Hyprland.focusedMonitor;
        window.screen = Quickshell.screens.find(s => focused && s.name === focused.name) || Quickshell.screens[0];
        forecast = null;
        phase = "updating";
        reason = "";
        // The window appears once the saved copy is read (a few milliseconds),
        // so the card opens at its full size instead of growing into it.
        saved.running = true;
    }
    function close() {
        if (closing || !opened) return;
        closing = true;
        opened = false;
        card.disappear();
    }
    Component.onCompleted: open()

    // The last forecast for the bar's current location, if there is one.
    Process {
        id: saved
        property int exitCode: -1
        property bool outDone: false
        command: [root.configDir + "/scripts/weather/forecast.sh", "--cached"]
        onStarted: { exitCode = -1; outDone = false; }
        function finish() {
            if (exitCode < 0 || !outDone) return;
            root.clock = Date.now() / 1000;
            root.forecast = exitCode === 0 ? root.parse(savedOut.text) : null;
            if (Model.fresh(root.forecast, root.clock)) root.phase = "ready";
            else fetcher.running = true;
            root.opened = true;
            card.appear();
        }
        stdout: StdioCollector { id: savedOut; onStreamFinished: { saved.outDone = true; saved.finish(); } }
        onExited: code => { saved.exitCode = code; saved.finish(); }
    }
    // forecast.sh prints the forecast and exits 0, or prints one reason line on
    // stderr and exits non-zero. Both streams and the exit must be in before deciding.
    Process {
        id: fetcher
        property int exitCode: -1
        property bool outDone: false
        property bool errDone: false
        command: [root.configDir + "/scripts/weather/forecast.sh"]
        onStarted: { exitCode = -1; outDone = false; errDone = false; }
        function finish() {
            if (exitCode < 0 || !outDone || !errDone) return;
            root.clock = Date.now() / 1000;
            const fetched = exitCode === 0 ? root.parse(fetchOut.text) : null;
            if (fetched) {
                root.forecast = fetched;
                root.phase = "ready";
                return;
            }
            root.reason = fetchErr.text.trim().split("\n").pop()
                || "The forecast request failed (exit " + exitCode + ").";
            root.phase = "failed";
        }
        stdout: StdioCollector { id: fetchOut; onStreamFinished: { fetcher.outDone = true; fetcher.finish(); } }
        stderr: StdioCollector { id: fetchErr; onStreamFinished: { fetcher.errDone = true; fetcher.finish(); } }
        onExited: code => { fetcher.exitCode = code; fetcher.finish(); }
    }
    Timer {
        interval: 30000
        repeat: true
        running: root.opened
        onTriggered: root.clock = Date.now() / 1000
    }

    IpcHandler {
        target: "weather"
        function ping(): string { return "ready"; }
        function toggle(): void { if (root.opened) root.close(); else root.open(); }
        function close(): void { root.close(); }
        function status(): string {
            return JSON.stringify({
                opened: root.opened, phase: root.phase, reason: root.reason,
                fetchedAt: root.forecast && typeof root.forecast.fetchedAt === "number" ? root.forecast.fetchedAt : -1,
                title: card.info.title, temp: card.info.temp, note: card.info.note,
                hours: card.info.hours.length, days: card.info.days.length
            });
        }
    }

    PanelWindow {
        id: window
        visible: root.opened || root.closing
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        // Normal: respect Waybar's exclusive zone, so the window starts just
        // below (or above) the bar and the card sits a gap away from it.
        exclusionMode: ExclusionMode.Normal
        WlrLayershell.namespace: "weather-popover"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        MouseArea { anchors.fill: parent; onClicked: root.close() }

        Card {
            id: card
            controller: root
            focus: true
            enabled: root.opened
            visible: root.opened || root.closing
            readonly property int edge: px(12)
            readonly property real anchorX: root.cursorX >= 0 ? root.cursorX - (window.screen ? window.screen.x : 0) : window.width / 2
            x: Math.max(edge, Math.min(window.width - width - edge, anchorX - width / 2))
            y: root.barAtBottom ? window.height - height - px(8) : px(8)

            // The update card's entrance: fade over 180 ms while scaling from
            // 97% and dropping 8 px over 220 ms, from the clicked point of the bar.
            property real fade: 0
            property real lift: 0
            opacity: fade
            transform: [
                Scale {
                    origin.x: Math.max(0, Math.min(card.width, card.anchorX - card.x))
                    origin.y: root.barAtBottom ? card.height : 0
                    xScale: 0.97 + 0.03 * card.lift
                    yScale: 0.97 + 0.03 * card.lift
                },
                Translate { y: (root.barAtBottom ? 1 : -1) * card.px(8) * (1 - card.lift) }
            ]
            function appear() {
                leave.stop();
                enter.start();
                forceActiveFocus();
            }
            function disappear() {
                enter.stop();
                leave.start();
            }
            ParallelAnimation {
                id: enter
                NumberAnimation { target: card; property: "fade"; to: 1; duration: 180; easing.type: Easing.OutCubic }
                NumberAnimation { target: card; property: "lift"; to: 1; duration: 220; easing.type: Easing.OutCubic }
            }
            ParallelAnimation {
                id: leave
                NumberAnimation { target: card; property: "fade"; to: 0; duration: 140; easing.type: Easing.InCubic }
                NumberAnimation { target: card; property: "lift"; to: 0; duration: 140; easing.type: Easing.InCubic }
                onFinished: if (root.closing) Qt.quit()
            }
        }
    }
}
