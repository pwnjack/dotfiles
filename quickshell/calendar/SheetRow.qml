import QtQuick
import QtQuick.Layouts

// One row of a sheet group: a label on the left, controls on the right.
RowLayout {
    id: row
    required property var card
    property string label: ""
    default property alias controls: slot.data
    Layout.fillWidth: true
    Layout.leftMargin: card.px(12)
    Layout.rightMargin: card.px(12)
    implicitHeight: Math.max(card.px(38), slot.implicitHeight)
    spacing: card.px(8)
    Text {
        text: row.label
        Layout.fillWidth: true
        color: row.card.c.foreground
        font.family: row.card.c.monoFont
        font.pixelSize: row.card.px(13)
    }
    Row {
        id: slot
        spacing: row.card.px(8)
    }
}
