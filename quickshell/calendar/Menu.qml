pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// A small list of choices under a row: {value, label, color?}; a tick on `current`.
Rectangle {
    id: menu
    required property var card
    property var items: []
    property string current: ""
    signal chosen(string value)
    implicitWidth: card.px(230)
    implicitHeight: col.implicitHeight + card.px(10)
    radius: card.px(12)
    z: 20
    color: Qt.rgba(card.c.background.r * 1.6, card.c.background.g * 1.6, card.c.background.b * 1.6, 0.98)
    border.width: 1
    border.color: Qt.rgba(card.c.foreground.r, card.c.foreground.g, card.c.foreground.b, 0.18)
    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: menu.card.px(5)
        spacing: 0
        Repeater {
            model: menu.items
            delegate: Rectangle {
                id: item
                required property var modelData
                required property int index
                objectName: "menuItem" + index
                Layout.fillWidth: true
                implicitHeight: menu.card.px(28)
                radius: menu.card.px(7)
                color: ihov.containsMouse ? Qt.rgba(menu.card.c.accent.r, menu.card.c.accent.g, menu.card.c.accent.b, 0.28) : "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: menu.card.px(9)
                    anchors.rightMargin: menu.card.px(9)
                    Rectangle {
                        visible: !!item.modelData.color
                        width: menu.card.px(9)
                        height: width
                        radius: width / 2
                        color: item.modelData.color || "transparent"
                    }
                    Text {
                        Layout.fillWidth: true
                        text: item.modelData.label
                        color: menu.card.c.foreground
                        font.family: menu.card.c.monoFont
                        font.pixelSize: menu.card.px(13)
                    }
                    Text {
                        objectName: "tick" + item.index
                        visible: item.modelData.value === menu.current
                        text: "✓"
                        color: menu.card.c.accent
                        font.pixelSize: menu.card.px(13)
                    }
                }
                MouseArea {
                    id: ihov
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: menu.chosen(item.modelData.value)
                }
            }
        }
    }
}
