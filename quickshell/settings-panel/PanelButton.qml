import QtQuick
import QtQuick.Controls

// The panel's push button. `primary` fills it with the accent, for the one action a
// row or group is waiting on (Apply); everything else is the quiet raised style.
// `danger` tones it red for an action that removes something (Sign out): red text
// on the quiet style, and a red fill when it is also primary (the confirmation).
Button {
    id: button
    required property var theme
    property bool primary: false
    property bool danger: false
    readonly property color red: "#c2484b"
    implicitHeight: 28
    leftPadding: 12
    rightPadding: 12
    hoverEnabled: true
    opacity: enabled ? 1 : 0.42
    contentItem: Text {
        text: button.text
        color: button.primary ? (button.danger ? "#ffffff" : button.theme.accentText) : button.danger ? button.theme.warn : button.theme.foreground
        font.pixelSize: 12
        font.weight: button.primary ? Font.DemiBold : Font.Normal
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        radius: 7
        readonly property color fill: button.danger ? button.red : button.theme.accent
        color: button.primary
            ? (button.down ? Qt.darker(fill, 1.15) : button.hovered ? Qt.lighter(fill, 1.08) : fill)
            : button.danger
                ? Qt.tint(button.theme.raised, Qt.rgba(button.red.r, button.red.g, button.red.b, button.down ? 0.34 : button.hovered ? 0.24 : 0.12))
                : (button.down ? button.theme.pressed : button.hovered ? button.theme.hover : button.theme.raised)
        border.width: button.activeFocus ? 2 : 1
        border.color: button.activeFocus ? (button.primary ? button.theme.foreground : button.theme.accent)
            : button.danger && !button.primary ? Qt.rgba(button.red.r, button.red.g, button.red.b, 0.4) : button.theme.line
        Behavior on color { ColorAnimation { duration: 100 } }
    }
}
