pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "model.mjs" as Model

// The media card for Waybar's custom/media. Started by
// scripts/hyprland/media-popover.sh; the process exits on close. Players come
// from Quickshell's MPRIS service, and the card opens on the one the bar
// shows (MEDIA_PLAYER, playerctl's name for it).
ShellRoot {
    id: root
    readonly property color background: Quickshell.env("MEDIA_BACKGROUND") || "#05090c"
    readonly property color foreground: Quickshell.env("MEDIA_FOREGROUND") || "#cfddde"
    readonly property color accent: Quickshell.env("MEDIA_ACCENT") || "#6097a1"
    readonly property string monoFont: Quickshell.env("MEDIA_FONT") || "monospace"
    // Global, so negative on an output left of the origin; NaN when unknown.
    readonly property real cursorX: Number(Quickshell.env("MEDIA_CURSOR_X") || "NaN")
    readonly property bool barAtBottom: Quickshell.env("MEDIA_BAR_POSITION") === "bottom"
    readonly property string wanted: Quickshell.env("MEDIA_PLAYER") || ""
    // A popover belongs to the bar, so it keeps the bar's own pixel sizes
    // instead of scaling with the output.
    readonly property real uiScale: 1

    property bool opened: false
    property bool closing: false
    // Until the window first appears: the player list fills a moment after
    // start, one player at a time.
    property bool settling: true
    readonly property var players: Mpris.players.values
    property var player: null
    property real position: 0   // seconds, the shown player's

    // Quickshell works the position out when it is read and never announces
    // it, so it is read: on a tick while playing, and when the player says
    // something changed.
    function sync() { position = player ? player.position : 0; }
    function show(next) { player = next; sync(); }
    function toggle() { if (player) player.togglePlaying(); }
    function next() { if (player) player.next(); }
    function previous() { if (player) player.previous(); }
    function seek(seconds) {
        if (!player) return;
        player.position = seconds;
        // Shown at once; the player's own answer follows.
        position = seconds;
    }
    // The bar polls every five seconds; a change made here shows at once.
    function refreshBar() { Quickshell.execDetached(["pkill", "-x", "-RTMIN+10", "waybar"]); }

    function appear(first) {
        settling = false;
        settle.stop();
        show(first);
        window.pickScreen();
        opened = true;
        window.appear();
    }
    function reopen() {
        // A click during the close fade cancels the close. opened before
        // closing, and closing before opened in close(): the window's visible
        // binding re-evaluates after each assignment, and a moment with both
        // false unmaps the layer (a blink).
        opened = true;
        closing = false;
        window.appear();
    }
    function close() {
        // Asked to close before the window appeared: nothing is on screen yet.
        if (!opened && !closing) { Qt.quit(); return; }
        if (closing) return;
        closing = true;
        opened = false;
        window.disappear();
    }

    onPlayersChanged: {
        if (settling) {
            const match = Model.named(players, wanted);
            if (match) appear(match);
            return;
        }
        // The shown player left the bus: another takes its place, and with
        // none left there is nothing to show.
        if (player && players.indexOf(player) >= 0) return;
        const rest = Model.pick(players, "");
        if (rest) show(rest);
        else close();
    }
    // The bar's player has not come: whichever there is, or nothing.
    Timer {
        id: settle
        interval: 300
        running: true
        onTriggered: {
            const first = Model.pick(root.players, root.wanted);
            if (first) root.appear(first);
            else Qt.quit();
        }
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.opened && root.player !== null && root.player.isPlaying
        onTriggered: root.sync()
    }
    Connections {
        target: root.player
        function onPositionChanged() { root.sync(); }
        function onPlaybackStateChanged() { root.sync(); root.refreshBar(); }
        function onPostTrackChanged() { root.sync(); root.refreshBar(); }
    }

    IpcHandler {
        target: "media"
        function ping(): string { return "ready"; }
        // Anything but a card that is fading out is closed by a second click,
        // one still waiting for its players included. A card fading out
        // because its last player left stays closed: there is nothing to show.
        function toggle(): void { if (root.closing && root.players.length > 0) root.reopen(); else root.close(); }
        function close(): void { root.close(); }
        function status(): string {
            const player = root.player;
            return JSON.stringify({
                opened: root.opened, players: root.players.length,
                player: player ? player.dbusName : "", identity: player ? player.identity : "",
                title: player ? player.trackTitle : "", artist: player ? player.trackArtist : "",
                playing: player ? player.isPlaying : false,
                position: root.position, length: player ? player.length : 0
            });
        }
    }

    BarPopover {
        id: window
        controller: root
        namespace: "media-popover"
        // The media module sits on the right of the bar.
        fallbackX: width
        Card { controller: root; focus: true }
    }
}
