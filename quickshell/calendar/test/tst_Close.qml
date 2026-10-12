import QtQuick
import QtTest

// The close order shell.qml uses: the PanelWindow is visible while the state is
// open or the card is still leaving. shell.qml cannot load under qmltestrunner
// (it imports Quickshell), so this fixture repeats its close() and visible binding.
Item {
    id: host
    width: 400; height: 300

    Item {
        id: shell
        property var state: ({ open: true })
        property bool closing: false
        property bool finished: false
        property real fade: 1
        readonly property bool windowVisible: state.open || closing
        // Every change of the visible expression, tagged with whether the leave animation had ended.
        property var seen: []
        onWindowVisibleChanged: seen.push({ visible: windowVisible, done: finished })

        NumberAnimation { id: leave; target: shell; property: "fade"; to: 0; duration: 140
            onFinished: { shell.finished = true; shell.closing = false; } }

        // The shell's close(), in its order; `oldOrder` reproduces the order that blinked.
        function close(oldOrder) {
            if (oldOrder) {
                state = ({ open: false });
                closing = true;
            } else {
                closing = true;
                state = ({ open: false });
            }
            leave.start();
        }
        function reset() { state = ({ open: true }); closing = false; finished = false; fade = 1; seen = []; }
    }

    TestCase {
        name: "Close"
        when: windowShown

        function test_window_never_drops_out_during_close() {
            shell.reset();
            shell.close(false);
            tryCompare(shell, "finished", true);
            const early = shell.seen.filter(s => !s.visible && !s.done);
            compare(early.length, 0, "the window read not visible before the leave animation ended");
        }

        // The control: the order that blinked must be caught by the same check.
        function test_the_old_order_is_caught() {
            shell.reset();
            shell.close(true);
            tryCompare(shell, "finished", true);
            verify(shell.seen.some(s => !s.visible && !s.done), "the check missed the one-frame blink");
        }
    }
}
