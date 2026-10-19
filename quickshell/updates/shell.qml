pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "model.mjs" as Model

// The update card for Waybar's custom/updates. Started by
// scripts/hyprland/updates-popover.sh; the process exits on close. The update
// itself runs in scripts/updates/updates-run.sh under setsid, so closing the
// card never stops it; reopening reads state.json and resumes the view.
ShellRoot {
    id: root
    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    readonly property string stateDir: Quickshell.env("UPDATES_STATE_DIR") || Quickshell.env("XDG_RUNTIME_DIR") + "/updates"
    readonly property color background: Quickshell.env("UPDATES_BACKGROUND") || "#05090c"
    readonly property color foreground: Quickshell.env("UPDATES_FOREGROUND") || "#cfddde"
    readonly property color accent: Quickshell.env("UPDATES_ACCENT") || "#6097a1"
    // Text on the accent. Not "onAccent": QML reads an on<Name> property as
    // the handler of <name>'s change signal.
    readonly property color accentInk: Quickshell.env("UPDATES_ON_ACCENT") || "#05090c"
    readonly property string monoFont: Quickshell.env("UPDATES_FONT") || "monospace"
    readonly property real cursorX: Number(Quickshell.env("UPDATES_CURSOR_X") || "-1")
    readonly property bool barAtBottom: Quickshell.env("UPDATES_BAR_POSITION") === "bottom"
    // The runner's test seam, honoured here too: the demo replay must not poke Waybar.
    readonly property bool signalBar: Quickshell.env("UPDATES_SIGNAL") !== "none"
    // A popover belongs to the bar, so it keeps the bar's own pixel sizes (the
    // mockup's px, at Waybar's 14px text) instead of scaling with the output
    // like the full-screen keybinds overlay: scaled, it was oversized at 1440p.
    readonly property real uiScale: 1

    property bool opened: false
    property bool closing: false
    property string mode: "summary"     // summary | running | result
    property var plan: null
    property string planError: ""
    // A saved plan is shown and a new check runs behind it.
    property bool refreshing: false
    property double clock: Date.now() / 1000   // epoch s, for "Checked 4 min ago"
    property var run: null
    property bool expanded: false
    property int requestedAt: 0         // epoch s of our Update press; older snapshots are ignored
    property double requestedMs: 0

    function readSnapshot() {
        stateFile.reload();
        try {
            const snap = JSON.parse(stateFile.text());
            return snap && snap.status ? snap : null;
        } catch (error) {
            return null;
        }
    }
    function readRun() {
        const snap = readSnapshot();
        if (snap && !(requestedAt && snap.startedAt < requestedAt)) run = snap;
    }
    // `acknowledge` is false for a result the card made up itself (the runner
    // died without a terminal state): there is no finishedAt to acknowledge.
    function showResult(acknowledge) {
        mode = "result";
        if (!acknowledge) return;
        ackFile.setText(String(run.finishedAt));
        // The bar keeps an unseen result's class until the ack exists.
        if (signalBar) barSignal.running = true;
    }
    // The run is dead and state.json does not say how it ended.
    function showLost() {
        const now = Math.floor(Date.now() / 1000);
        run = { status: "attention", errorKind: "unknown", progress: 0, total: 0, done: 0, restart: "",
                error: "The update stopped without reporting how it ended.",
                detail: "Its log is " + stateDir + "/run.log",
                startedAt: requestedAt || now, finishedAt: now };
        showResult(false);
    }

    // Liveness is the runner's run.lock, the bar module's rule: a held lock is
    // a run (0% until its first snapshot), and "running" with a free lock is
    // stale. The probe reads /proc/locks instead of trying the lock: a
    // momentary `flock -n` here could make a starting runner find the lock
    // taken and exit as "busy".
    Process {
        id: lockProbe
        property var then: null
        command: ["bash", "-c", "f=$1; [ -e \"$f\" ] || exit 1\n"
            + "read -r maj min ino < <(stat -L -c '%Hd %Ld %i' -- \"$f\") || exit 1\n"
            + "grep -q \" $(printf '%02x:%02x:%s' \"$maj\" \"$min\" \"$ino\") \" /proc/locks",
            "bash", root.stateDir + "/run.lock"]
        onExited: code => {
            const then = lockProbe.then;
            lockProbe.then = null;
            if (then) then(code === 0);
        }
    }
    function probeLock(then) {
        if (lockProbe.running) return;
        lockProbe.then = then;
        lockProbe.running = true;
    }

    function open() {
        if (opened) return;
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
        expanded = false;
        requestedAt = 0;
        run = null;
        plan = null;
        planError = "";
        refreshing = false;
        clock = Date.now() / 1000;
        probeLock(held => root.decide(held));
    }
    function decide(held) {
        const snap = readSnapshot();
        ackFile.reload();
        if (held) {
            // The runner deletes the old state right after taking the lock.
            run = snap && snap.status === "running" ? snap : null;
            mode = "running";
            card.shown = run ? run.progress : 0;
        } else if (snap && snap.status !== "running" && ackFile.text().trim() !== String(snap.finishedAt)) {
            run = snap;
            showResult(true);
        } else {
            mode = "summary";
            savedPlan.running = true;
        }
        opened = true;
        card.appear();
    }
    function close() {
        if (closing) return;
        closing = true;
        opened = false;
        card.disappear();
    }
    function start() {
        if (mode !== "summary" || !plan || !plan.repo.length) return;
        requestedAt = Math.floor(Date.now() / 1000);
        requestedMs = Date.now();
        run = null;
        mode = "running";
        runner.running = true;
    }
    function toggleList() { expanded = !expanded; }
    function terminal(kind) {
        terminalLauncher.command = ["setsid", "-f", configDir + "/scripts/updates/terminal.sh", kind];
        terminalLauncher.running = true;
    }
    function reboot() { rebooter.running = true; }
    Component.onCompleted: open()

    FileView { id: stateFile; path: root.stateDir + "/state.json"; blockLoading: true; printErrors: false }
    FileView { id: ackFile; path: root.stateDir + "/ack"; blockLoading: true; printErrors: false; atomicWrites: true }

    // Poll while a run is shown: the fold replaces state.json by rename, and
    // the file may not exist yet when the card starts the run. Every eighth
    // tick (~1 s) also checks that the runner is still alive.
    Timer {
        property int tick: 0
        interval: 120
        repeat: true
        running: root.opened && root.mode === "running"
        onTriggered: {
            root.readRun();
            if (root.run && root.run.status !== "running") {
                root.showResult(true);
                return;
            }
            tick += 1;
            if (tick % 8) return;
            root.probeLock(held => {
                if (held || root.mode !== "running") return;
                // The runner writes its terminal state before it lets go of the lock.
                root.readRun();
                if (root.run && root.run.status !== "running") root.showResult(true);
                // setsid -f returns before the runner takes the lock: give it time.
                else if (!root.requestedMs || Date.now() - root.requestedMs > 3000) root.showLost();
            });
        }
    }

    // The last check's plan, unless pacman's database changed since
    // (updates-plan.sh --cached). Fresh, it is the whole answer; older, it
    // stays on screen while the planner checks again; none, the planner runs
    // as if nothing was saved.
    Process {
        id: savedPlan
        property int exitCode: -1
        property bool outDone: false
        command: [root.configDir + "/scripts/updates/updates-plan.sh", "--cached"]
        function finish() {
            if (exitCode < 0 || !outDone) return;
            let saved = null;
            try {
                saved = exitCode === 0 ? JSON.parse(savedOut.text) : null;
                if (saved && (!Array.isArray(saved.repo) || !Array.isArray(saved.aur))) saved = null;
            } catch (error) {
                saved = null;
            }
            // Nothing to show any more: the card closed or an Update began.
            if (root.mode !== "summary" || root.plan || root.planError) return;
            root.clock = Date.now() / 1000;
            if (saved) root.plan = saved;
            if (Model.planFresh(saved, root.clock)) return;
            root.refreshing = !!saved;
            planner.running = true;
        }
        stdout: StdioCollector { id: savedOut; onStreamFinished: { savedPlan.outDone = true; savedPlan.finish(); } }
        onExited: code => { savedPlan.exitCode = code; savedPlan.finish(); }
    }
    Timer {
        interval: 15000
        repeat: true
        running: root.opened && root.mode === "summary"
        onTriggered: root.clock = Date.now() / 1000
    }

    // updates-plan.sh prints JSON and exits 0, or prints one reason line on
    // stderr and exits 1. Both streams and the exit must be in before deciding.
    Process {
        id: planner
        property int exitCode: -1
        property bool outDone: false
        property bool errDone: false
        command: [root.configDir + "/scripts/updates/updates-plan.sh"]
        function finish() {
            if (exitCode < 0 || !outDone || !errDone) return;
            root.refreshing = false;
            root.clock = Date.now() / 1000;
            // An Update pressed during a re-check made this answer moot.
            if (root.mode !== "summary") return;
            const reason = planErr.text.trim().split("\n").pop();
            if (exitCode !== 0) {
                root.planError = reason || "The update check failed (exit " + exitCode + ").";
                return;
            }
            try {
                const plan = JSON.parse(planOut.text);
                if (!Array.isArray(plan.repo) || !Array.isArray(plan.aur)) throw new Error("no repo/aur arrays");
                root.plan = plan;
            } catch (error) {
                root.planError = "The update check returned no plan.";
            }
        }
        stdout: StdioCollector { id: planOut; onStreamFinished: { planner.outDone = true; planner.finish(); } }
        stderr: StdioCollector { id: planErr; onStreamFinished: { planner.errDone = true; planner.finish(); } }
        onExited: code => { planner.exitCode = code; planner.finish(); }
    }
    // Detached with no tie to this process: run.log has the whole stream, and
    // nothing the runner prints may go to the pipes of a card that has exited.
    Process {
        id: runner
        command: ["bash", "-c", "setsid -f \"$1\" </dev/null >/dev/null 2>&1", "bash",
            root.configDir + "/scripts/updates/updates-run.sh"]
    }
    Process { id: terminalLauncher; onExited: root.close() }
    Process { id: rebooter; command: ["systemctl", "reboot"]; onExited: root.close() }
    Process { id: barSignal; command: ["pkill", "-RTMIN+9", "waybar"] }

    IpcHandler {
        target: "updates"
        function ping(): string { return "ready"; }
        function toggle(): void { if (root.opened) root.close(); else root.open(); }
        function close(): void { root.close(); }
        function status(): string {
            return JSON.stringify({
                opened: root.opened, mode: root.mode, expanded: root.expanded,
                pending: root.plan ? root.plan.repo.length + root.plan.aur.length + (root.plan.flatpak || 0) : -1,
                planError: root.planError,
                refreshing: root.refreshing,
                checkedAt: root.plan && typeof root.plan.checkedAt === "number" ? root.plan.checkedAt : -1,
                run: root.run ? { status: root.run.status, progress: root.run.progress, line: root.run.line } : null,
                shown: card.shown
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
        WlrLayershell.namespace: "updates-popover"
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
            readonly property real anchorX: root.cursorX >= 0 ? root.cursorX - (window.screen ? window.screen.x : 0) : window.width
            x: Math.max(edge, Math.min(window.width - width - edge, anchorX - width / 2))
            y: root.barAtBottom ? window.height - height - px(8) : px(8)

            // The mockup's entrance: fade over 180 ms while scaling from 97%
            // and dropping 8 px over 220 ms, from the clicked point of the bar.
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
                armKeys();
                enter.start();
                focusPrimary();
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
