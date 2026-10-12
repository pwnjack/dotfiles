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
    // The list fades in as the card grows to hold it, rather than appearing ahead of the frame.
    Connections { target: up.card.c; function onStateChanged() { if (up.card.c.state.unfolded && !up.wasUnfolded) reveal.restart(); up.wasUnfolded = up.card.c.state.unfolded; } }
    property bool wasUnfolded: card.c.state.unfolded
    property real listOpacity: 1
    NumberAnimation { id: reveal; target: up; property: "listOpacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
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
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: up.card.c.openSettings() }
    }
    // Folded it answers "what's next?"; unfolded it titles the list. The chevron
    // stays in one place and turns, so the bar reads as one control either way.
    SectionHeader {
        objectName: "upcomingHeader"
        visible: !up.noAccount
        Layout.fillWidth: true
        card: up.card
        whole: !!up.summary.next || up.card.c.state.unfolded
        showButton: whole
        turn: up.card.c.state.unfolded ? -90 : 90
        text: up.card.c.state.unfolded ? "Upcoming · 7 days"
            : up.summary.next
                ? "Next · " + (up.summary.next.allDay ? "" : Model.formatTime(Model.minutesOf(up.summary.next.startEpoch), up.card.c.clock,
                    up.card.c.locale.amText, up.card.c.locale.pmText) + " ") + up.summary.next.title
                  + (up.summary.more ? " · +" + up.summary.more + " more" : "")
                : "Nothing in the next 7 days"
        label.objectName: "foldedLine"
        label.color: up.summary.next || up.card.c.state.unfolded ? up.card.c.foreground : up.card.dim
        onClicked: up.card.c.toggleUpcoming()
    }
    Text { visible: !up.noAccount && up.card.c.state.unfolded && !up.groups.length; text: "Nothing in the next 7 days"
        Layout.leftMargin: up.card.px(12); Layout.topMargin: up.card.px(6)
        color: up.card.dim; font.family: up.card.c.monoFont; font.pixelSize: up.card.px(13) }
    Repeater {
        id: list
        model: !up.noAccount && up.card.c.state.unfolded ? up.groups : []
        delegate: ColumnLayout {
            id: group
            required property var modelData
            Layout.fillWidth: true
            opacity: up.listOpacity
            spacing: 0
            Text { text: up.dayTitle(group.modelData.key); color: up.card.dim; font.family: up.card.c.monoFont
                font.pixelSize: up.card.px(12); Layout.topMargin: up.card.px(8); Layout.leftMargin: up.card.px(12)
                Layout.bottomMargin: up.card.px(2) }
            Repeater { model: group.modelData.events; delegate: EventRow { required property var modelData; card: up.card; event: modelData } }
        }
    }
}
