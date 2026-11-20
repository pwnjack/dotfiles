import QtQuick
import QtQuick.Controls

Button {
    id: control
    required property var theme
    implicitHeight: 46
    implicitWidth: Math.max(46, contentItem.implicitWidth + 32)
    hoverEnabled: true
    Accessible.name: text
    contentItem: Text {
        text: control.text
        textFormat: Text.PlainText
        font.family: "sans-serif"
        font.pixelSize: 14
        font.weight: Font.Medium
        color: control.theme.foreground
        opacity: control.enabled ? 1 : 0.4
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        radius: 23
        color: control.theme.background
        opacity: control.down ? 0.65 : control.hovered ? 1 : 0.85
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? control.theme.accent : Qt.alpha(control.theme.foreground, 0.2)
    }
}
