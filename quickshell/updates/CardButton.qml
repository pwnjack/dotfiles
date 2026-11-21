import QtQuick

// A card button: primary (accent), ghost (hairline) or warn (amber), with an
// optional key hint, as in the mockup.
Rectangle {
    id: button
    required property var card
    property string text
    property string hint
    property string kind: "ghost"
    signal clicked()

    readonly property color ink: kind === "primary" ? card.accentInk : kind === "warn" ? card.warnInk : card.foreground
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: if (enabled) clicked()
    implicitWidth: row.implicitWidth + card.px(32)
    implicitHeight: card.px(34)
    radius: card.px(10)
    color: kind === "primary" ? (mouse.containsMouse ? Qt.lighter(card.accent, 1.12) : card.accent)
         : kind === "warn" ? card.warn
         : mouse.containsMouse ? Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.08) : "transparent"
    border.width: kind === "ghost" ? 1 : 0
    border.color: Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.18)
    scale: mouse.pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: 100 } }
    Behavior on color { ColorAnimation { duration: 150 } }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -button.card.px(3)
        radius: button.radius + button.card.px(3)
        color: "transparent"
        border.width: 2
        border.color: button.card.foreground
        visible: button.activeFocus
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: button.card.px(6)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: button.text
            color: button.ink
            font.family: button.card.monoFont
            font.pixelSize: button.card.px(13)
            font.weight: Font.Medium
        }
        // The mockup's <kbd>: muted on a ghost button, the button's ink on a filled one.
        Rectangle {
            visible: button.hint !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: hintText.implicitWidth + button.card.px(8)
            height: hintText.implicitHeight + button.card.px(2)
            radius: button.card.px(4)
            color: "transparent"
            border.width: 1
            border.color: button.kind === "ghost" ? button.card.hairline : Qt.rgba(button.ink.r, button.ink.g, button.ink.b, 0.3)
            Text {
                id: hintText
                anchors.centerIn: parent
                text: button.hint
                color: button.kind === "ghost" ? button.card.dim : button.ink
                font.family: button.card.monoFont
                font.pixelSize: button.card.px(10.5)
            }
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
    function activate(event) {
        event.accepted = true;
        if (card.keysArmed()) button.clicked();
    }
    Keys.onReturnPressed: event => activate(event)
    Keys.onEnterPressed: event => activate(event)
    Keys.onSpacePressed: event => activate(event)
}
