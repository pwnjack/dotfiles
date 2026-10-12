pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "model.mjs" as Model

// The selected day: its timeline, its events, and a way to add one on it.
// The header's × (or Esc, or a second click on the day) puts Upcoming back;
// the month stays where it is. Only + and "New event on…" start an event.
ColumnLayout {
    id: dv
    required property var card
    readonly property string day: card.c.state.day || ""
    readonly property var events: card.c.dayFor === day ? card.c.dayEvents : []
    readonly property bool hasTimed: events.some(e => !e.allDay)
    readonly property var dayDate: new Date(Model.dayStart(day || "1970-01-01") * 1000)
    // Without an account nothing can be added.
    readonly property bool canAdd: !(!!card.c.status && card.c.status.state === "none")
    spacing: card.px(6)
    // A day (or the next one picked) fades in while the card resizes around it.
    onDayChanged: if (day) reveal.restart()
    onVisibleChanged: if (visible) reveal.restart()
    NumberAnimation { id: reveal; target: dv; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
    SectionHeader {
        objectName: "dayHeader"
        Layout.fillWidth: true
        card: dv.card
        text: dv.card.c.locale.toString(dv.dayDate, "dddd d MMMM")
        glyph: "×"
        glyphSize: 20
        onClicked: dv.card.c.closeDay()
    }
    // A day with only all-day events (or none) has nothing to draw on the strip.
    Timeline { objectName: "timeline"; visible: dv.hasTimed; Layout.fillWidth: true; Layout.topMargin: dv.card.px(4)
        card: dv.card; day: dv.day; events: dv.events }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Repeater { model: dv.events; delegate: EventRow { required property var modelData; card: dv.card; event: modelData } }
    }
    Text { visible: !dv.events.length; text: "Nothing on this day"; color: dv.card.dim
        Layout.leftMargin: dv.card.px(12); Layout.topMargin: dv.card.px(2)
        font.family: dv.card.c.monoFont; font.pixelSize: dv.card.px(13) }
    Rectangle {
        objectName: "newOnDayButton"
        visible: dv.canAdd
        Layout.fillWidth: true; Layout.topMargin: dv.card.px(2)
        implicitHeight: dv.card.px(34); radius: dv.card.px(10)
        color: Qt.rgba(dv.card.c.accent.r, dv.card.c.accent.g, dv.card.c.accent.b, newHover.containsMouse ? 0.12 : 0)
        Behavior on color { ColorAnimation { duration: 100 } }
        border.width: 1
        border.color: Qt.rgba(dv.card.c.accent.r, dv.card.c.accent.g, dv.card.c.accent.b, 0.45)
        Text { objectName: "newOnDay"; x: dv.card.px(12); anchors.verticalCenter: parent.verticalCenter
            text: "+ New event on " + dv.card.c.locale.toString(dv.dayDate, "ddd d")
            color: dv.card.c.accent; font.family: dv.card.c.monoFont; font.pixelSize: dv.card.px(13) }
        MouseArea { id: newHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dv.card.c.newEvent(dv.day) }
    }
}
