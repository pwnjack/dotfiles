pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "model.mjs" as Model

// The card's frame: header (long date, sync status, Today, +) over the body
// for the current state. The reading views sit in `body`; the sheet (Task 11) replaces them.
FocusScope {
    id: card
    required property var controller
    signal dismissed()
    readonly property var c: controller
    function px(v) { return Math.round(v * c.uiScale); }
    readonly property color dim: Qt.rgba(c.foreground.r, c.foreground.g, c.foreground.b, 0.62)
    readonly property color line: Qt.rgba(c.foreground.r, c.foreground.g, c.foreground.b, 0.10)
    readonly property bool browsedAway: {
        const d = new Date();
        return !!c.state.day || c.state.year || c.viewYear !== d.getFullYear() || c.viewMonth !== d.getMonth();
    }
    width: px(372)
    height: frame.height
    property real fade: 0
    property real lift: 0
    opacity: fade
    transform: Translate { y: (card.c.barAtBottom ? 1 : -1) * card.px(8) * (1 - card.lift) }
    function appear() { leave.stop(); enter.start(); forceActiveFocus(); }
    function disappear() { enter.stop(); leave.start(); }
    ParallelAnimation {
        id: enter
        NumberAnimation { target: card; property: "fade"; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: card; property: "lift"; to: 1; duration: 220; easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: leave
        NumberAnimation { target: card; property: "fade"; to: 0; duration: 140; easing.type: Easing.InCubic }
        NumberAnimation { target: card; property: "lift"; to: 0; duration: 140; easing.type: Easing.InCubic }
        onFinished: card.dismissed()
    }
    Keys.onEscapePressed: event => { card.c.act("esc"); event.accepted = true; }
    // ↓ below the month grid's last row (the grid passes it on) unfolds Upcoming.
    Keys.onDownPressed: event => {
        if (card.c.state.open && !card.c.state.unfolded && !card.c.state.sheet && !card.c.state.day && !card.c.state.year) {
            card.c.toggleUpcoming(); event.accepted = true;
        }
    }

    // Hover previews: one tip shared by the month cells, Upcoming rows and timeline blocks.
    property var peekEvents: []
    property string peekHeading: ""
    property var peekAnchor: null
    property string peekPending: ""
    function peekDay(item, key) {
        const from = Model.dayStart(key), to = Model.dayStart(Model.addDays(key, 1));
        const known = c.agenda.filter(e => e.startEpoch < to && e.endEpoch > from);
        peekHeading = c.locale.toString(new Date(from * 1000), "dddd d MMMM");
        peekAnchor = item;
        peekEvents = known;
        if (!known.length) { peekPending = key; c.loadPeek(key); }
    }
    Connections { target: card.c; function onPeekEventsChanged() {
        if (card.peekPending && card.c.peekFor === card.peekPending) { card.peekEvents = card.c.peekEvents; card.peekPending = ""; } } }
    function unpeek(item) { if (peekAnchor === item) { peekEvents = []; peekAnchor = null; peekPending = ""; } }
    function showTip(item, events) { peekHeading = ""; peekAnchor = item; peekEvents = events; }
    EventTip {
        card: card
        events: card.peekEvents
        heading: card.peekHeading
        readonly property point at: card.peekAnchor ? card.peekAnchor.mapToItem(card, 0, card.peekAnchor.height) : Qt.point(0, 0)
        x: Math.max(0, Math.min(card.width - width, at.x))
        y: at.y + card.px(4)
    }

    Rectangle {
        id: frame
        width: parent.width
        height: content.implicitHeight + card.px(32)
        radius: card.px(18)
        color: Qt.rgba(card.c.background.r, card.c.background.g, card.c.background.b, 0.82)
        border.width: 1
        border.color: Qt.rgba(card.c.foreground.r, card.c.foreground.g, card.c.foreground.b, 0.14)
        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent }       // clicks inside never reach the close catcher
        ColumnLayout {
            id: content
            x: card.px(16); y: card.px(16)
            width: parent.width - card.px(32)
            spacing: card.px(12)
            RowLayout {
                objectName: "header"
                visible: !card.c.state.sheet
                Layout.fillWidth: true
                spacing: card.px(10)
                // The text column gives up width (elided) so Today and + keep their places.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 0
                    Text { objectName: "longDate"; Layout.fillWidth: true; elide: Text.ElideRight
                        text: card.c.locale.toString(new Date(), "dddd d MMMM yyyy")
                        color: card.c.foreground; font.family: card.c.monoFont; font.pixelSize: card.px(15); font.weight: Font.DemiBold }
                    Text { objectName: "syncStatus"; Layout.fillWidth: true; elide: Text.ElideRight
                        text: card.c.headerStatus()
                        color: card.c.status && card.c.status.state === "failed" ? "#eaa3a4" : card.dim
                        font.family: card.c.monoFont; font.pixelSize: card.px(12.5) }
                }
                HeaderButton { objectName: "todayButton"; visible: card.browsedAway; label: "Today"; card: card; onClicked: card.c.goToday() }
                HeaderButton { objectName: "plusButton"; label: "+"; card: card; square: true
                    enabled: card.c.status && card.c.status.state !== "none"; onClicked: card.c.newEvent(card.c.state.day || null) }
            }
            ColumnLayout {
                id: body
                objectName: "body"
                visible: !card.c.state.sheet
                Layout.fillWidth: true
                spacing: card.px(10)
                MonthGrid {
                    id: month
                    visible: !card.c.state.year
                    Layout.fillWidth: true
                    card: card
                    selected: card.c.state.day || ""
                    focus: !card.c.state.sheet
                    onPicked: key => card.c.selectDay(key)
                    onPrev: card.c.shiftMonth(-1)
                    onNext: card.c.shiftMonth(1)
                    onTitleClicked: card.c.showYear()
                }
                YearGrid { visible: card.c.state.year; Layout.fillWidth: true; card: card }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: card.line }
                Upcoming { visible: !card.c.state.day; Layout.fillWidth: true; card: card }
                DayView { visible: !!card.c.state.day; Layout.fillWidth: true; card: card }
            }
        }
    }
}
