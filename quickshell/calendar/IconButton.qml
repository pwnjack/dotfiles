import QtQuick

// A round glyph button: the month and year arrows, Upcoming's chevron, the
// day's close. One size and one hover tint, so every icon on the card sits on
// the same 28 px target. `turn` rotates the glyph (the chevron folds by turning).
Rectangle {
    id: button
    required property var card
    property string glyph: ""
    property real turn: 0
    property real glyphSize: 16
    // Optical centring: a glyph's ink is not centred in its line box.
    property real nudgeY: 0
    signal clicked()
    implicitWidth: card.px(28)
    implicitHeight: card.px(28)
    radius: width / 2
    color: Qt.rgba(card.c.foreground.r, card.c.foreground.g, card.c.foreground.b, hov.containsMouse ? 0.12 : 0)
    Behavior on color { ColorAnimation { duration: 100 } }
    Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: button.card.px(button.nudgeY)
        text: button.glyph
        rotation: button.turn
        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        color: button.card.c.accent
        font.family: button.card.c.monoFont
        font.pixelSize: button.card.px(button.glyphSize)
        font.weight: Font.DemiBold
    }
    MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: button.clicked() }
}
