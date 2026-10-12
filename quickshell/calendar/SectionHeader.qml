import QtQuick

// The bar over the section under the month: Upcoming (folded or not) and the
// selected day share it, so its title and its button never move between them.
// With `whole` the entire bar is the button (Upcoming folds from anywhere on it).
Rectangle {
    id: header
    required property var card
    property string text: ""
    property string glyph: "›"
    property real turn: 0
    property real glyphSize: 16
    property real nudgeY: 0
    property bool whole: false
    property bool showButton: true
    property alias label: title
    signal clicked()
    implicitHeight: card.px(34)
    radius: card.px(10)
    color: Qt.rgba(card.c.foreground.r, card.c.foreground.g, card.c.foreground.b, header.whole && rowHover.containsMouse ? 0.10 : 0.06)
    Behavior on color { ColorAnimation { duration: 100 } }
    MouseArea { id: rowHover; anchors.fill: parent; enabled: header.whole; hoverEnabled: true
        cursorShape: Qt.PointingHandCursor; onClicked: header.clicked() }
    Text {
        id: title
        x: header.card.px(12)
        anchors.verticalCenter: parent.verticalCenter
        width: (button.visible ? button.x - header.card.px(6) : parent.width - header.card.px(12)) - x
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: header.text
        color: header.card.c.foreground
        font.family: header.card.c.monoFont
        font.pixelSize: header.card.px(13)
    }
    IconButton {
        id: button
        visible: header.showButton
        card: header.card
        anchors.right: parent.right
        anchors.rightMargin: header.card.px(3)
        anchors.verticalCenter: parent.verticalCenter
        glyph: header.glyph
        turn: header.turn
        glyphSize: header.glyphSize
        nudgeY: header.nudgeY
        onClicked: header.clicked()
    }
}
