pragma ComponentBehavior: Bound
import QtQuick

// The next hours, three apart: the hour, its condition and its temperature.
// Eight slots fill the card; an aged forecast with fewer keeps their width.
Row {
    id: strip
    required property var card
    property var hours: []
    readonly property real slot: width / 8

    Repeater {
        objectName: "slots"
        model: strip.hours
        Column {
            id: hour
            required property var modelData
            width: strip.slot
            spacing: strip.card.px(6)
            Text {
                objectName: "label"
                anchors.horizontalCenter: parent.horizontalCenter
                text: hour.modelData.label
                color: hour.modelData.now ? strip.card.accent : strip.card.dim
                font.family: strip.card.monoFont
                font.pixelSize: strip.card.px(11.5)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: hour.modelData.glyph
                color: strip.card.foreground
                font.family: strip.card.monoFont
                font.pixelSize: strip.card.px(17)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: hour.modelData.temp
                color: strip.card.foreground
                font.family: strip.card.monoFont
                font.pixelSize: strip.card.px(12.5)
            }
        }
    }
}
