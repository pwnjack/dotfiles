pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "model.mjs" as Model

// The selected day: its timeline, its events, and a way to add one on it.
ColumnLayout {
    id: dv
    required property var card
    readonly property string day: card.c.state.day || ""
    readonly property var events: card.c.dayFor === day ? card.c.dayEvents : []
    readonly property var dayDate: new Date(Model.dayStart(day || "1970-01-01") * 1000)
    spacing: card.px(6)
    RowLayout {
        Layout.fillWidth: true
        Text { Layout.fillWidth: true; text: dv.card.c.locale.toString(dv.dayDate, "dddd d MMMM")
            color: dv.card.dim; font.family: dv.card.c.monoFont; font.pixelSize: dv.card.px(12) }
        Text { text: "Upcoming ›"; color: dv.card.c.accent; font.family: dv.card.c.monoFont; font.pixelSize: dv.card.px(12)
            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: dv.card.c.act("esc") } }
    }
    Timeline { Layout.fillWidth: true; card: dv.card; day: dv.day; events: dv.events
        onGapClicked: minutes => dv.card.c.newEvent(dv.day, minutes) }
    Repeater { model: dv.events; delegate: EventRow { required property var modelData; card: dv.card; event: modelData } }
    Text { visible: !dv.events.length; text: "Nothing on this day"; color: dv.card.dim
        font.family: dv.card.c.monoFont; font.pixelSize: dv.card.px(13) }
    Rectangle {
        objectName: "newOnDayButton"
        Layout.fillWidth: true; Layout.topMargin: dv.card.px(4)
        implicitHeight: dv.card.px(34); radius: dv.card.px(10)
        color: "transparent"; border.width: 1
        border.color: Qt.rgba(dv.card.c.foreground.r, dv.card.c.foreground.g, dv.card.c.foreground.b, 0.3)
        Text { objectName: "newOnDay"; x: dv.card.px(10); anchors.verticalCenter: parent.verticalCenter
            text: "+ New event on " + dv.card.c.locale.toString(dv.dayDate, "ddd d")
            color: dv.card.c.accent; font.family: dv.card.c.monoFont; font.pixelSize: dv.card.px(13) }
        MouseArea { anchors.fill: parent; onClicked: dv.card.c.newEvent(dv.day) }
    }
}
