pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// The year: ‹ YYYY ›, 12 months with their event counts; a click zooms in.
ColumnLayout {
    id: year
    objectName: "yearView"
    required property var card
    readonly property var counts: card.c.counts[String(card.c.viewYear)] || []
    spacing: card.px(6)
    // Wheel up goes back a year, as in the month grid.
    WheelHandler { onWheel: event => { if (event.angleDelta.y > 0) year.card.c.shiftYear(-1); else if (event.angleDelta.y < 0) year.card.c.shiftYear(1); } }
    RowLayout {
        Layout.fillWidth: true
        Text { text: "‹"; color: year.card.c.accent; font.pixelSize: year.card.px(18)
            MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: year.card.c.shiftYear(-1) } }
        Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: year.card.c.viewYear
            color: year.card.c.foreground; font.family: year.card.c.monoFont; font.pixelSize: year.card.px(13); font.weight: Font.DemiBold }
        Text { text: "›"; color: year.card.c.accent; font.pixelSize: year.card.px(18)
            MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: year.card.c.shiftYear(1) } }
    }
    GridLayout {
        columns: 3; columnSpacing: year.card.px(6); rowSpacing: year.card.px(6)
        Layout.fillWidth: true
        Repeater {
            model: 12
            delegate: Rectangle {
                id: m
                required property int index
                readonly property bool current: index === new Date().getMonth() && year.card.c.viewYear === new Date().getFullYear()
                objectName: "yearMonth" + index
                Layout.fillWidth: true
                implicitHeight: year.card.px(48)
                radius: year.card.px(10)
                color: current ? year.card.c.accent : Qt.rgba(year.card.c.foreground.r, year.card.c.foreground.g, year.card.c.foreground.b, hov.containsMouse ? 0.10 : 0.05)
                Column {
                    anchors.centerIn: parent
                    Text { anchors.horizontalCenter: parent.horizontalCenter
                        text: year.card.c.locale.standaloneMonthName(m.index, Locale.ShortFormat)
                        color: m.current ? year.card.c.accentInk : year.card.c.foreground; font.family: year.card.c.monoFont; font.pixelSize: year.card.px(13) }
                    Text { anchors.horizontalCenter: parent.horizontalCenter
                        text: year.counts.length ? (year.counts[m.index] || "·") : ""
                        color: m.current ? year.card.c.accentInk : year.card.dim; font.family: year.card.c.monoFont; font.pixelSize: year.card.px(12) }
                }
                MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true; onClicked: year.card.c.pickMonth(m.index) }
            }
        }
    }
}
