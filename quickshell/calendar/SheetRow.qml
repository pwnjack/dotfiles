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
    // A layout computes its own implicit height, so the row's height is a layout hint:
    // 40 px around 30 px pills leaves the same 5 px above and below every control.
    Layout.preferredHeight: Math.max(card.px(40), slot.implicitHeight)
    spacing: card.px(8)
    // The width the controls may take: the row less its label.
    readonly property real room: width - title.implicitWidth - spacing
    Text {
        id: title
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
