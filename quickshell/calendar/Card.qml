pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// The card's frame: header (long date, sync status, Today, +) over the body
// for the current state. Views are added in Tasks 10 and 11 into `body`.
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
            Item { id: body; objectName: "body"; Layout.fillWidth: true; implicitHeight: childrenRect.height }
        }
    }
}
