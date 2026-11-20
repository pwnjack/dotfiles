pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
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
    // Global, so negative on an output left of the origin; NaN when unknown.
    readonly property real cursorX: Number(Quickshell.env("WEATHER_CURSOR_X") || "NaN")
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
            window.appear();
            return;
        }
        window.pickScreen();
        forecast = null;
        phase = "updating";
        reason = "";
        // The window appears once the saved copy is read (a few milliseconds),
        // so the card opens at its full size instead of growing into it.
        saved.running = true;
    }
    function close() {
        // Asked to close before the saved copy was read: nothing is on screen yet.
        if (!opened && !closing) { Qt.quit(); return; }
        if (closing) return;
        closing = true;
        opened = false;
        window.disappear();
    }
    Component.onCompleted: open()

    // The last forecast for the bar's current location, if there is one.
    Collect {
        id: saved
        command: [root.configDir + "/scripts/weather/forecast.sh", "--cached"]
        onDone: (code, out) => {
            root.clock = Date.now() / 1000;
            root.forecast = code === 0 ? root.parse(out) : null;
            if (Model.fresh(root.forecast, root.clock)) root.phase = "ready";
            else fetcher.running = true;
            root.opened = true;
            window.appear();
        }
    }
    // forecast.sh prints the forecast and exits 0, or prints one reason line on
    // stderr and exits non-zero.
    Collect {
        id: fetcher
        command: [root.configDir + "/scripts/weather/forecast.sh"]
        onDone: (code, out, err) => {
            root.clock = Date.now() / 1000;
            const fetched = code === 0 ? root.parse(out) : null;
            if (fetched) {
                root.forecast = fetched;
                root.phase = "ready";
                return;
            }
            root.reason = err.trim().split("\n").pop()
                || "The forecast request failed (exit " + code + ").";
            root.phase = "failed";
        }
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
        // Anything but a card that is fading out is closed by a second click,
        // one still reading its saved copy included.
        function toggle(): void { if (root.closing) root.open(); else root.close(); }
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

    BarPopover {
        id: window
        controller: root
        namespace: "weather-popover"
        // The weather module sits in the middle of the bar.
        fallbackX: width / 2
        Card { id: card; controller: root; focus: true }
    }
}
