import QtQuick
import QtTest
import ".."
import "../model.mjs" as Model

Item {
    id: host
    width: 1600
    height: 900

    // The controller API shell.qml provides, backed by the real model.
    QtObject {
        id: controller
        property color background: "#05090c"
        property color foreground: "#cfddde"
        property color accent: "#6097a1"
        property color accentInk: "#05090c"
        // The font the strip ships with (the launcher passes options/font).
        property string monoFont: "FiraCode Nerd Font"
        property real uiScale: 1
        property var state: Model.initialState({}, "screenshot")
        property var status: Model.parseStatus("")
        property int runs: 0
        property int closes: 0
        function apply(result) { state = result.state; }
        function setMode(mode) { state = Model.withMode(state, mode); }
        function setTarget(target) { apply(Model.setOption(state, Model.targetKey(state.mode), target)); }
        function toggleOption(key) { apply(Model.setOption(state, key, !state[key])); }
        function cycleDelay() { apply(Model.setOption(state, "delay", Model.nextDelay(state.delay))); }
        function key(name) {
            const result = Model.reduceKey(state, name);
            apply(result);
            if (result.effect === "close") close();
            else if (result.effect === "run") run();
        }
        function run() { runs += 1; }
        function close() { closes += 1; }
    }
    Strip {
        id: strip
        controller: controller
        focus: true
    }
    TestCase {
        name: "Capture"
        when: windowShown

        function init() {
            controller.state = Model.initialState({}, "screenshot");
            controller.status = Model.parseStatus("");
            controller.runs = 0;
            controller.closes = 0;
            strip.forceActiveFocus();
            wait(20);
        }
        function labelOf(name) { return findChild(findChild(strip, name), "label"); }

        function test_fixedWidth() {
            const shot = strip.width;
            verify(shot > 0);
            const target = findChild(strip, "target-region");
            const targetX = target.mapToItem(strip, 0, 0).x;
            const actionX = findChild(strip, "action").mapToItem(strip, 0, 0).x;
            controller.setMode("text");
            wait(20);
            compare(strip.width, shot);
            compare(findChild(strip, "action").mapToItem(strip, 0, 0).x, actionX, "the action does not move on Text");
            controller.setMode("screenshot");
            wait(20);
            compare(target.mapToItem(strip, 0, 0).x, targetX);
            controller.setMode("record");
            wait(20);
            compare(strip.width, shot);
            controller.status = { phase: "recording", seconds: 35999 };
            wait(20);
            compare(strip.width, shot);
        }
        function test_controlsPerMode() {
            verify(findChild(strip, "screenshot-freeze").visible);
            verify(findChild(strip, "screenshot-annotate").visible);
            verify(!findChild(strip, "record-audio").visible);
            controller.setMode("record");
            wait(20);
            verify(findChild(strip, "record-audio").visible);
            verify(findChild(strip, "record-mic").visible);
            verify(!findChild(strip, "screenshot-freeze").visible);
            controller.setMode("text");
            wait(20);
            verify(findChild(strip, "shot-delay").visible);
            verify(findChild(strip, "screenshot-freeze").visible);
            verify(!findChild(strip, "target-region").visible, "Text has no target selector");
            verify(!findChild(strip, "screenshot-annotate").visible);
            verify(!findChild(strip, "record-audio").visible);
        }
        function test_noElidedLabel() {
            // The tab labels are left out: they have no width constraint, so they cannot elide by construction.
            const names = ["target-screen", "target-window", "target-region",
                "shot-delay", "screenshot-freeze", "screenshot-annotate",
                "rec-delay", "record-audio", "record-mic", "action"];
            for (const name of names) verify(!labelOf(name).truncated, name + " is elided");
            controller.setMode("text");
            wait(20);
            compare(labelOf("action").text, "Copy text");
            verify(!labelOf("action").truncated, "Copy text is elided");
            controller.setMode("record");
            controller.status = { phase: "recording", seconds: 35999 };
            wait(20);
            controller.status = { phase: "countdown", seconds: 10 };
            wait(20);
            compare(labelOf("action").text, "Cancel 10");
            verify(!labelOf("action").truncated, "Cancel 10 is elided");
            controller.status = Model.parseStatus("");
            wait(20);
            compare(labelOf("action").text, "Record");
            verify(!labelOf("action").truncated, "Record is elided");
            controller.status = { phase: "recording", seconds: 35999 };
            wait(20);
            compare(labelOf("action").text, "Stop 9:59:59");
            verify(!labelOf("action").truncated, "Stop 9:59:59 is elided");
        }
        function test_targetClickOnlySelects() {
            mouseClick(findChild(strip, "target-window"));
            compare(controller.state.shotTarget, "window");
            compare(controller.runs, 0);
        }
        function test_delayCycles() {
            mouseClick(findChild(strip, "shot-delay"));
            compare(controller.state.delay, 3);
            compare(labelOf("shot-delay").text, "3s");
        }
        function test_keys() {
            keyClick(Qt.Key_Tab);
            compare(controller.state.mode, "text");
            keyClick(Qt.Key_Tab);
            compare(controller.state.mode, "record");
            keyClick(Qt.Key_Return);
            compare(controller.runs, 1);
            keyClick(Qt.Key_Escape);
            compare(controller.closes, 1);
        }
        function test_held_keys_act_once() {
            const before = controller.runs;
            verify(strip.handleKey(Qt.Key_Return, true), "the held key is still claimed");
            compare(controller.runs, before, "an auto-repeated Return is ignored");
        }
        function test_arrows_move_and_clamp() {
            compare(controller.state.shotTarget, "region");
            keyClick(Qt.Key_Right);
            compare(controller.state.shotTarget, "region");
            keyClick(Qt.Key_Left);
            compare(controller.state.shotTarget, "window");
            keyClick(Qt.Key_Left);
            keyClick(Qt.Key_Left);
            compare(controller.state.shotTarget, "screen");
        }
        function test_backtab_switches_mode() {
            keyClick(Qt.Key_Backtab);
            compare(controller.state.mode, "record", "Shift+Tab wraps backwards from Screenshot");
            keyClick(Qt.Key_Backtab);
            compare(controller.state.mode, "text");
            keyClick(Qt.Key_Backtab);
            compare(controller.state.mode, "screenshot");
        }
        function test_textTab() {
            mouseClick(findChild(strip, "tab-text"));
            compare(controller.state.mode, "text");
            wait(20);
            verify(Qt.colorEqual(findChild(strip, "tab-text").color, controller.accent));
            keyClick(Qt.Key_Left);
            keyClick(Qt.Key_Right);
            compare(controller.state.shotTarget, "region", "arrows do nothing on Text");
            mouseClick(findChild(strip, "shot-delay"));
            compare(controller.state.delay, 3);
            compare(labelOf("shot-delay").text, "3s");
            mouseClick(findChild(strip, "screenshot-freeze"));
            compare(controller.state.freeze, true);
            compare(controller.runs, 0);
        }
        function test_target_click_does_not_close() {
            mouseClick(findChild(strip, "target-screen"));
            compare(controller.closes, 0);
            compare(controller.runs, 0);
        }
        function test_actionTooltipShowsItsText() {
            const tip = findChild(strip, "action-tip");
            verify(tip, "the action tooltip exists");
            const cases = [
                ["screenshot", { phase: "idle", seconds: 0 }],
                ["text", { phase: "idle", seconds: 0 }],
                ["record", { phase: "idle", seconds: 0 }],
                ["record", { phase: "recording", seconds: 42 }]];
            for (const [mode, status] of cases) {
                controller.setMode(mode);
                controller.status = status;
                wait(20);
                verify(tip.text !== "", mode + " " + status.phase + ": tooltip text is set");
                compare(tip.contentItem.text, tip.text, mode + " " + status.phase);
            }
        }
        function test_tabColour() {
            verify(Qt.colorEqual(findChild(strip, "tab-screenshot").color, controller.accent));
            controller.setMode("record");
            wait(20);
            verify(Qt.colorEqual(findChild(strip, "tab-record").color, "#ff5555"));
        }
    }
}
