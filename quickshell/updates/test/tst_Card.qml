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
        property bool refreshing: false
        property double clock: 100000
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
            controller.refreshing = false;
            controller.lastTerminal = "";
            card.forceActiveFocus();
            card.focusPrimary();
            tryCompare(findChild(card, "listClip"), "height", 0, 1000);
            wait(50);
        }
        function test_spinnerWhileChecking() {
            controller.plan = null;
            // Every view has a Header; look inside the summary one.
            const spinner = findChild(card.activeView, "spinner");
            verify(spinner !== null);
            tryCompare(spinner, "opacity", 1, 1000);
            controller.plan = controller.fullPlan;
            tryCompare(spinner, "opacity", 0, 1000);
            controller.plan = null;
            tryCompare(spinner, "opacity", 1, 1000);
            controller.planError = "checkupdates failed";
            tryCompare(spinner, "opacity", 0, 1000);
        }
        // A saved plan says how old it is; one being re-checked says so and spins.
        function test_checkedLine() {
            const line = findChild(card.activeView, "checked");
            const spinner = findChild(card.activeView, "spinner");
            verify(line !== null);
            compare(line.text, "", "a plan without checkedAt has no line");
            controller.plan = Object.assign({}, controller.fullPlan, { checkedAt: controller.clock - 240 });
            compare(line.text, "4 min ago");
            tryCompare(spinner, "opacity", 0, 1000);
            // The longest lines still fit beside Later and Update.
            for (const age of [59 * 60, 23 * 3600]) {
                controller.plan = Object.assign({}, controller.fullPlan, { checkedAt: controller.clock - age });
                verify(!line.truncated, "'" + line.text + "' is cut short");
            }
            controller.refreshing = true;
            compare(line.text, "Checking…");
            verify(!line.truncated, "'Checking…' is cut short");
            tryCompare(spinner, "opacity", 1, 1000);
            verify(card.activeView.canUpdate, "the saved plan can still be updated");
            controller.refreshing = false;
            controller.planError = "offline";
            compare(line.text, "", "an error has no freshness line");
        }
        function test_listCollapsedByDefault() {
            const clip = findChild(card, "listClip");
            verify(clip !== null);
            compare(clip.height, 0);
            controller.toggleList();
            tryVerify(() => clip.height > 0, 1000);
        }
        // The frame moves with the list, not a beat behind it.
        function test_frameTracksList() {
            const clip = findChild(card, "listClip");
            const fits = () => Math.abs(card.height - card.activeView.implicitHeight - card.px(34)) < 1;
            tryVerify(fits, 1000);
            for (const expand of [true, false]) {
                controller.toggleList();
                let between = 0;
                for (let i = 0; i < 40; i++) {
                    wait(10);
                    if (clip.height > 0 && clip.height < card.activeView.listHeight) between += 1;
                    verify(fits(), "frame " + card.height + " trails content " + card.activeView.implicitHeight);
                }
                verify(between > 2, "the list animates");
                compare(clip.height, expand ? card.activeView.listHeight : 0);
            }
        }
        // A toggle while the frame still eases to the arriving plan takes
        // over from the list's first frame (one catch-up step, no trailing).
        function test_frameTracksListMidEase() {
            const fits = () => Math.abs(card.height - card.activeView.implicitHeight - card.px(34)) < 1;
            const full = card.activeView.implicitHeight;
            controller.plan = null;
            tryVerify(() => card.activeView.implicitHeight < full && fits(), 1000);
            controller.plan = controller.fullPlan;
            wait(60);
            verify(!fits(), "the frame is still easing");
            const collapsed = card.activeView.implicitHeight;
            controller.toggleList();
            tryVerify(() => card.activeView.implicitHeight > collapsed, 1000);
            for (let i = 0; i < 40; i++) {
                wait(10);
                verify(fits(), "frame " + card.height + " trails content " + card.activeView.implicitHeight);
            }
        }
        // A re-check swapping the plan re-arms the key guard.
        function test_returnIgnoredAfterPlanSwap() {
            wait(card.activationDelay);
            controller.plan = Object.assign({}, controller.fullPlan, { bytes: 1 });
            keyClick(Qt.Key_Return);
            compare(controller.starts, 0);
            wait(card.activationDelay);
            keyClick(Qt.Key_Return);
            compare(controller.starts, 1);
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
