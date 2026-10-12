import QtQuick

// The sheet's switch, drawn as the panel's PanelSwitch is: a 38×22 track whose
// 18 px knob slides, in the card's colours. It reports a click through toggled()
// and never flips `checked` itself; the owner sets it from the draft.
Item {
    id: toggle
    required property var card
    property bool checked: false
    signal toggled()
    implicitWidth: 38
    implicitHeight: 28
    opacity: enabled ? 1 : 0.42
    activeFocusOnTab: true
    Keys.onSpacePressed: event => { toggle.toggled(); event.accepted = true; }
    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: 38; height: 22; radius: 11
        color: toggle.checked ? toggle.card.c.accent
            : Qt.rgba(toggle.card.c.foreground.r, toggle.card.c.foreground.g, toggle.card.c.foreground.b, 0.18)
        border.width: toggle.activeFocus ? 2 : 0
        border.color: toggle.card.c.foreground
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle {
            width: 18; height: 18; radius: 9; y: 2
            x: toggle.checked ? 18 : 2
            color: toggle.checked ? toggle.card.c.accentInk : toggle.card.c.foreground
            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
    }
    MouseArea {
        anchors.fill: parent
        enabled: toggle.enabled
        cursorShape: toggle.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: { toggle.forceActiveFocus(); toggle.toggled(); }
    }
}
