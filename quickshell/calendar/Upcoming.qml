pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "model.mjs" as Model

// Folded: one line answering "what's next?". Unfolded: the next 7 days by day.
// With no account, the only thing here is the way to set one up.
ColumnLayout {
    id: up
    required property var card
    readonly property var summary: Model.upcomingSummary(card.c.agenda, card.c.now)
    readonly property var groups: Model.groupUpcoming(card.c.agenda, card.c.now, 7)
    readonly property string todayKey: Model.dayKey(card.c.now)
    readonly property bool noAccount: !!card.c.status && card.c.status.state === "none"
    spacing: card.px(4)
    function dayTitle(key) {
        if (key === todayKey) return "Today";
        if (key === Model.addDays(todayKey, 1)) return "Tomorrow";
        return card.c.locale.toString(new Date(Model.dayStart(key) * 1000), "ddd d");
    }
    Rectangle {
        objectName: "setUpRow"
        visible: up.noAccount
        Layout.fillWidth: true; implicitHeight: up.card.px(36); radius: up.card.px(10)
        color: Qt.rgba(up.card.c.accent.r, up.card.c.accent.g, up.card.c.accent.b, 0.18)
        Text { anchors.centerIn: parent; text: "Set up iCloud in Settings ›"; color: up.card.c.foreground
            font.family: up.card.c.monoFont; font.pixelSize: up.card.px(13) }
        MouseArea { anchors.fill: parent; onClicked: up.card.c.openSettings() }
    }
    Rectangle {
        visible: !up.noAccount && !up.card.c.state.unfolded
        Layout.fillWidth: true; implicitHeight: up.card.px(34); radius: up.card.px(10)
        color: Qt.rgba(up.card.c.foreground.r, up.card.c.foreground.g, up.card.c.foreground.b, foldHover.containsMouse ? 0.10 : 0.06)
        Text {
            objectName: "foldedLine"
            x: up.card.px(10); anchors.verticalCenter: parent.verticalCenter; width: parent.width - up.card.px(20)
            elide: Text.ElideRight; textFormat: Text.PlainText
            text: up.summary.next
                ? "Next · " + (up.summary.next.allDay ? "" : Model.formatTime(Model.minutesOf(up.summary.next.startEpoch), up.card.c.clock,
                    up.card.c.locale.amText, up.card.c.locale.pmText) + " ") + up.summary.next.title
                  + (up.summary.more ? " · +" + up.summary.more + " this week" : "") + "  ⌄"
                : "Nothing in the next 7 days"
            color: up.card.c.foreground; font.family: up.card.c.monoFont; font.pixelSize: up.card.px(13)
        }
        MouseArea { id: foldHover; anchors.fill: parent; hoverEnabled: true; onClicked: if (up.summary.next) up.card.c.toggleUpcoming() }
    }
    RowLayout {
        visible: !up.noAccount && up.card.c.state.unfolded
        Layout.fillWidth: true
        Text { text: "Upcoming · 7 days"; color: up.card.dim; font.family: up.card.c.monoFont; font.pixelSize: up.card.px(12); Layout.fillWidth: true }
        Text { text: "⌃"; color: up.card.c.accent; font.pixelSize: up.card.px(14)
            MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: up.card.c.toggleUpcoming() } }
    }
    Text { visible: !up.noAccount && up.card.c.state.unfolded && !up.groups.length; text: "Nothing in the next 7 days"
        color: up.card.dim; font.family: up.card.c.monoFont; font.pixelSize: up.card.px(13) }
    Repeater {
        model: !up.noAccount && up.card.c.state.unfolded ? up.groups : []
        delegate: ColumnLayout {
            id: group
            required property var modelData
            Layout.fillWidth: true
            spacing: up.card.px(1)
            Text { text: up.dayTitle(group.modelData.key); color: up.card.dim; font.family: up.card.c.monoFont
                font.pixelSize: up.card.px(12); Layout.topMargin: up.card.px(6) }
            Repeater { model: group.modelData.events; delegate: EventRow { required property var modelData; card: up.card; event: modelData } }
        }
    }
}
