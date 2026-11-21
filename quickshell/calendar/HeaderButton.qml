import QtQuick

// The header's "Today" and "+" buttons.
Rectangle {
    id: button
    required property var card
    property string label: ""
    property bool square: false
    // A glyph-only button says what it does; a worded one says its label.
    property string name: label
    signal clicked()
    width: square ? card.px(30) : labelText.implicitWidth + card.px(20)
    height: card.px(30)
    radius: card.px(9)
    opacity: enabled ? 1 : 0.4
    Accessible.role: Accessible.Button
    Accessible.name: name
    Accessible.onPressAction: if (enabled) clicked()
    color: Qt.rgba(card.c.accent.r, card.c.accent.g, card.c.accent.b, hover.containsMouse ? 0.32 : 0.22)
    Text { id: labelText; anchors.centerIn: parent; text: button.label; color: button.card.c.foreground
        font.family: button.card.c.monoFont; font.pixelSize: button.card.px(button.square ? 18 : 12.5); font.weight: Font.Bold; Accessible.ignored: true }
    MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; enabled: button.enabled
        cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: button.clicked() }
}
