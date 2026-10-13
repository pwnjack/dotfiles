import QtQuick
import QtTest
import ".."

Item {
    id: host
    width: 1600
    height: 900

    QtObject {
        id: controller
        property color background: "#05090c"
        property color foreground: "#cfddde"
        property color accent: "#6097a1"
        property color accentInk: "#05090c"
        property string monoFont: "monospace"
        property real uiScale: 1
        property string mode: "summary"
        readonly property var fullPlan: ({ repo: [
                { name: "mesa", old: "1:26.2.1-1", new: "1:26.2.2-1", bytes: 1, kernel: false },
                { name: "firefox", old: "152.0-1", new: "152.0.1-1", bytes: 1, kernel: false },
                { name: "waybar", old: "0.14.0-3", new: "0.14.1-1", bytes: 1, kernel: false }],
            aur: [{ name: "spotblock-git", old: "1-1", new: "2-1" }], bytes: 115867648, kernel: false })
        property var plan: fullPlan
        property string planError: ""
        property var run: null
        property bool expanded: false
        property int starts: 0
        property int closes: 0
        property int reboots: 0
        property string lastTerminal: ""
        function start() { starts += 1; }
        function close() { closes += 1; }
        function toggleList() { expanded = !expanded; }
        function terminal(kind) { lastTerminal = kind; }
        function reboot() { reboots += 1; }
    }
    Card {
        id: card
        controller: controller
        focus: true
    }
    TestCase {
        name: "Card"
        when: windowShown

        function init() {
            controller.mode = "summary";
            controller.run = null;
            controller.expanded = false;
            controller.starts = 0;
            controller.closes = 0;
            controller.reboots = 0;
            controller.plan = controller.fullPlan;
            controller.planError = "";
            controller.lastTerminal = "";
            card.forceActiveFocus();
            card.focusPrimary();
            wait(50);
        }
        function test_spinnerWhileChecking() {
            controller.plan = null;
            const spinner = findChild(card, "spinner");
            verify(spinner !== null);
            tryCompare(spinner, "opacity", 1, 1000);
            verify(spinner.visible);
            controller.plan = controller.fullPlan;
            tryCompare(spinner, "opacity", 0, 1000);
            controller.plan = null;
            tryCompare(spinner, "opacity", 1, 1000);
            controller.planError = "checkupdates failed";
            tryCompare(spinner, "opacity", 0, 1000);
        }
        function test_listCollapsedByDefault() {
            const clip = findChild(card, "listClip");
            verify(clip !== null);
            compare(clip.height, 0);
            controller.toggleList();
            tryVerify(() => clip.height > 0, 1000);
        }
        function test_returnStartsOnce() {
            wait(card.activationDelay);
            keyClick(Qt.Key_Return);
            compare(controller.starts, 1);
        }
        function test_aurLinkOpensAurPath() {
            const link = findChild(card, "terminalLink");
            tryVerify(() => link.visible, 1000);
            mouseClick(link);
            compare(controller.lastTerminal, "aur");
        }
        function test_flatpakOnlyHasTerminalPath() {
            controller.plan = { repo: [], aur: [], bytes: 0, kernel: false, flatpak: 2 };
            const link = findChild(card, "terminalLink");
            tryVerify(() => link.visible, 1000);
            mouseClick(link);
            compare(controller.lastTerminal, "flatpak");
            compare(controller.starts, 0);
        }
        function test_escapeCloses() {
            keyClick(Qt.Key_Escape);
            compare(controller.closes, 1);
        }
        function test_attentionShowsReason() {
            controller.run = { status: "attention", errorKind: "pacman", total: 1, startedAt: 0, finishedAt: 5,
                error: "failed to commit transaction (conflicting files)",
                detail: "python-pywal16: /usr/bin/wal exists in filesystem (owned by python-pywal)", restart: "" };
            controller.mode = "result";
            const reason = findChild(card, "reason");
            tryVerify(() => reason.visible, 1000);
            verify(reason.text.indexOf("exists in filesystem") >= 0);
        }
        function test_progressGlides() {
            controller.run = { status: "running", progress: 0.5, key: "install", line: "Installing mesa · 1 of 3",
                total: 3, startedAt: 0, finishedAt: 0 };
            controller.mode = "running";
            tryVerify(() => card.shown > 0.45, 3000);
            verify(card.shown <= 0.5);
        }
        function test_restartIgnoresEarlyReturn() {
            controller.run = { status: "restart", restart: "7.2.9-1-cachyos", errorKind: "", total: 2,
                startedAt: 0, finishedAt: 8 };
            controller.mode = "result";
            wait(50);
            keyClick(Qt.Key_Return);
            compare(controller.reboots, 0);
            wait(card.activationDelay);
            keyClick(Qt.Key_Return);
            compare(controller.reboots, 1);
        }
        function test_doneClosesItself() {
            controller.run = { status: "done", total: 3, startedAt: 0, finishedAt: 102, errorKind: "", restart: "" };
            controller.mode = "result";
            tryCompare(controller, "closes", 1, 4500);
        }
    }
}
