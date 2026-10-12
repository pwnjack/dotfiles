import QtQuick
import QtQuick.Layouts
import "model.mjs" as Model

// One event: time range (or "all day"), calendar dot, title. Hover -> details, click -> edit.
Rectangle {
    id: row
    objectName: "eventRow"
    required property var card
    required property var event
    readonly property bool lit: card.c.highlight !== "" && event.title === card.c.highlight
    Layout.fillWidth: true
    implicitHeight: card.px(28)
    radius: card.px(8)
    // A row opens its event, so it lights under the pointer like every other button on the card.
    color: lit ? Qt.rgba(card.c.accent.r, card.c.accent.g, card.c.accent.b, 0.25)
        : Qt.rgba(card.c.foreground.r, card.c.foreground.g, card.c.foreground.b, hov.containsMouse ? 0.08 : 0)
    Behavior on color { ColorAnimation { duration: row.lit ? 400 : 100 } }
    function fmt(s) { return Model.formatTime(Model.minutesOf(s), card.c.clock, card.c.locale.amText, card.c.locale.pmText); }
    // The time column is as wide as the widest range the clock can print, so the dots line up and the title takes the rest.
    TextMetrics { id: widest; font.family: row.card.c.monoFont; font.pixelSize: row.card.px(13)
        text: row.card.c.clock === "12h" ? "00:00 " + row.card.c.locale.pmText + "–00:00 " + row.card.c.locale.pmText : "00:00–00:00" }
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: row.card.px(12)
        anchors.rightMargin: row.card.px(12)
        spacing: row.card.px(10)
        Text { objectName: "eventTime"; Layout.preferredWidth: widest.advanceWidth; Layout.minimumWidth: widest.advanceWidth
            text: row.event.allDay ? "all day" : row.fmt(row.event.startEpoch) + "–" + row.fmt(row.event.endEpoch)
            color: row.card.c.accent; font.family: row.card.c.monoFont; font.pixelSize: row.card.px(13) }
        Rectangle { objectName: "eventDot"; width: row.card.px(9); height: width; radius: width / 2; color: row.event.color || row.card.c.accent }
        Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: row.event.title; elide: Text.ElideRight
            color: row.card.c.foreground; font.family: row.card.c.monoFont; font.pixelSize: row.card.px(13) }
    }
    MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: containsMouse ? row.card.showTip(row, [row.event]) : row.card.unpeek(row)
        onClicked: row.card.c.editEvent(row.event) }
}
