import QtQuick

// A volume track and its percentage. While pressed, and for a moment after a
// commit, it shows its own value: PipeWire echoes volumes late, and an echo
// must not pull the handle from under the pointer. It commits on release and
// on each wheel or arrow step (2 %), never while dragging, and always within
// [0, max]. A volume above `max` (software gain set elsewhere) parks the
// handle at the end and the label keeps the true percentage. A commit goes to
// the `key` the gesture started on: if `key` changed by the release (the
// default moved, the stream ended), the drag is dropped.
Item {
    id: slider
    required property var popover
    property string key: ""
    property real value: 0
    property real max: 1
    property bool muted: false
    signal commit(string key, real value)

    property real held: 0
    property string pressedKey: ""
    readonly property bool pressed: mouse.pressed
    readonly property bool holding: pressed || settling.running
    readonly property real level: holding ? held : value
    readonly property real step: 0.02
    implicitHeight: popover.px(22)
    activeFocusOnTab: true

    function round(v) { return Math.round(v * 100) / 100; }
    function at(x) {
        return round(Math.max(0, Math.min(1, (x - track.x) / track.width)) * max);
    }
    function send(v) {
        if (!key) return;
        held = v;
        settling.restart();
        commit(key, v);
    }
    // Up never lowers an over-range volume; down from one lands within max.
    function nudge(notches) {
        const base = settling.running ? held : round(value);
        const next = round(Math.max(0, Math.min(max, base + notches * step)));
        if (notches > 0 && next < base) return;
        if (next !== base) send(next);
    }
    // Ends early once the controller reports the committed value.
    Timer { id: settling; interval: 1000 }
    onValueChanged: if (settling.running && Math.abs(value - held) < 0.005) settling.stop()
    // Another device or stream: show its own volume at once.
    onKeyChanged: settling.stop()

    Keys.onRightPressed: nudge(1)
    Keys.onUpPressed: nudge(1)
    Keys.onLeftPressed: nudge(-1)
    Keys.onDownPressed: nudge(-1)

    Rectangle {
        id: track
        objectName: "track"
        x: handle.width / 2
        width: percent.x - slider.popover.px(8) - handle.width
        height: slider.popover.px(6)
        anchors.verticalCenter: parent.verticalCenter
        radius: height / 2
        color: Qt.rgba(slider.popover.foreground.r, slider.popover.foreground.g, slider.popover.foreground.b, 0.14)
        Rectangle {
            width: handle.x + handle.width / 2 - track.x
            height: parent.height
            radius: parent.radius
            color: slider.muted ? slider.popover.dim : slider.popover.accent
        }
    }
    Rectangle {
        id: handle
        objectName: "handle"
        width: slider.popover.px(14)
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: track.x + track.width * Math.min(slider.level, slider.max) / slider.max - width / 2
        color: slider.popover.foreground
        border.width: slider.activeFocus ? 2 : 0
        border.color: slider.popover.accent
        scale: slider.pressed ? 1.15 : 1
        Behavior on scale { NumberAnimation { duration: 100 } }
    }
    Text {
        id: percent
        objectName: "percent"
        x: parent.width - width
        width: slider.popover.px(42)
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        text: Math.round(slider.level * 100) + " %"
        color: slider.popover.dim
        font.family: slider.popover.monoFont
        font.pixelSize: slider.popover.px(12)
        font.features: ({ "tnum": 1 })
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        // A press on the percentage is not a press on the track.
        onPressed: event => {
            if (event.x > track.x + track.width + handle.width) {
                event.accepted = false;
                return;
            }
            settling.stop();
            slider.pressedKey = slider.key;
            slider.held = slider.at(event.x);
        }
        onPositionChanged: event => slider.held = slider.at(event.x)
        onReleased: if (slider.key === slider.pressedKey) slider.send(slider.held)
        // Touchpads send fractions of a notch: steps fire as whole notches add up.
        property real wheelRest: 0
        onWheel: event => {
            wheelRest += event.angleDelta.y / 120;
            const notches = wheelRest > 0 ? Math.floor(wheelRest) : Math.ceil(wheelRest);
            wheelRest -= notches;
            if (notches) slider.nudge(notches);
        }
    }
}
