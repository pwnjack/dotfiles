pragma ComponentBehavior: Bound
import QtQuick
import "model.mjs" as Model

// One day as a strip: existing events as blocks, an optional draft as a dashed
// outline with its clashes hatched, today's past hatched with a now line.
// Clicking a free spot emits gapClicked(minutes); hovering a block shows its events.
Item {
    id: tl
    required property var card
    property string day: ""
    property var events: []
    property var draft: null
    signal gapClicked(int minutes)
    readonly property var timed: Model.lanes(events.filter(e => !e.allDay))
    readonly property var range: Model.timelineRange(events, draft, day)
    readonly property bool twoLanes: timed.some(e => e.lane === 1)
    readonly property bool isToday: day !== "" && day === Model.dayKey(card.c.now)
    readonly property real nowX: !day ? 0 : (((card.c.now - Model.dayStart(day)) / 3600) - range.from) / (range.to - range.from)
    implicitHeight: strip.height + ticksRow.height + card.px(4)
    Rectangle {
        id: strip
        width: parent.width
        height: tl.card.px(tl.twoLanes ? 44 : 28)
        radius: tl.card.px(7)
        color: Qt.rgba(tl.card.c.foreground.r, tl.card.c.foreground.g, tl.card.c.foreground.b, 0.05)
        MouseArea {
            id: free
            anchors.fill: parent
            hoverEnabled: true
            onClicked: mouse => tl.gapClicked(Model.minutesAt(mouse.x / width, tl.range))
        }
        Rectangle {   // past hours, today only
            visible: tl.isToday && tl.nowX > 0
            width: parent.width * Math.min(1, tl.nowX); height: parent.height; radius: parent.radius
            color: Qt.rgba(tl.card.c.foreground.r, tl.card.c.foreground.g, tl.card.c.foreground.b, 0.07)
        }
        Repeater {
            model: tl.timed
            delegate: Rectangle {
                id: blk
                required property var modelData
                readonly property var seg: Model.segment(modelData, tl.day, tl.range)
                x: seg.left * strip.width; width: Math.max(2, seg.width * strip.width)
                y: modelData.lane === 0 ? tl.card.px(4) : tl.card.px(22)
                height: tl.card.px(modelData.lane === 0 && !tl.twoLanes ? 20 : 18)
                radius: tl.card.px(5)
                color: modelData.color || tl.card.c.accent
                border.width: bhov.containsMouse ? 2 : 0; border.color: tl.card.c.foreground
                Text {
                    id: label
                    x: tl.card.px(6); anchors.verticalCenter: parent.verticalCenter
                    text: blk.modelData.title + (blk.seg.cut ? " ›" : "")
                    visible: implicitWidth + tl.card.px(12) <= blk.width       // whole, or not at all
                    color: "#05090c"; font.family: tl.card.c.monoFont; font.pixelSize: tl.card.px(12); font.weight: Font.DemiBold
                }
                MouseArea { id: bhov; anchors.fill: parent; hoverEnabled: true
                    onContainsMouseChanged: containsMouse
                        ? tl.card.showTip(blk, tl.timed.filter(e => e.startEpoch < blk.modelData.endEpoch && e.endEpoch > blk.modelData.startEpoch))
                        : tl.card.unpeek(blk) }
            }
        }
        Repeater {   // clashes, hatched
            model: tl.draft ? Model.clashes(tl.draft, tl.timed) : []
            delegate: Rectangle {
                required property var modelData
                readonly property real a: Math.max(modelData.startEpoch, tl.draft.start)
                readonly property real b: Math.min(modelData.endEpoch, tl.draft.end)
                readonly property var seg: Model.segment({ startEpoch: a, endEpoch: b }, tl.day, tl.range)
                x: seg.left * strip.width; width: seg.width * strip.width
                y: tl.card.px(4); height: tl.card.px(20)
                color: "#e0787a"; opacity: 0.75; radius: tl.card.px(3)
            }
        }
        Rectangle {   // the draft
            visible: !!tl.draft && !tl.draft.allDay
            readonly property var seg: tl.draft ? Model.segment({ startEpoch: tl.draft.start, endEpoch: tl.draft.end }, tl.day, tl.range) : ({ left: 0, width: 0 })
            x: seg.left * strip.width; width: seg.width * strip.width
            y: tl.card.px(1); height: strip.height - tl.card.px(2)
            radius: tl.card.px(6); color: Qt.rgba(1, 1, 1, 0.10)
            border.width: 2; border.color: tl.card.c.foreground
        }
        Rectangle {   // where a click would put the event
            visible: free.containsMouse && !!tl.draft
            readonly property real hoverStart: Model.minutesAt(free.mouseX / strip.width, tl.range) / 60
            readonly property real length: tl.draft ? (tl.draft.end - tl.draft.start) / 3600 : 1
            x: (hoverStart - tl.range.from) / (tl.range.to - tl.range.from) * strip.width
            width: length / (tl.range.to - tl.range.from) * strip.width
            y: tl.card.px(2); height: strip.height - tl.card.px(4)
            radius: tl.card.px(6); color: "transparent"; border.width: 1
            border.color: Qt.rgba(tl.card.c.foreground.r, tl.card.c.foreground.g, tl.card.c.foreground.b, 0.45)
        }
        Rectangle { visible: tl.isToday && tl.nowX > 0 && tl.nowX < 1; x: tl.nowX * strip.width; y: -tl.card.px(3)
            width: 2; height: strip.height + tl.card.px(6); color: tl.card.c.foreground }
    }
    Item {
        id: ticksRow
        anchors.top: strip.bottom; anchors.topMargin: tl.card.px(4)
        width: parent.width; height: tl.card.px(16)
        Repeater {
            model: tl.day ? Model.ticks(tl.range.from, tl.range.to) : []
            delegate: Text {
                required property int modelData
                required property int index
                readonly property real fx: (modelData - tl.range.from) / (tl.range.to - tl.range.from)
                x: Math.max(0, Math.min(ticksRow.width - implicitWidth, fx * ticksRow.width - implicitWidth / 2))
                text: String(modelData).padStart(2, "0")
                color: tl.card.dim; font.family: tl.card.c.monoFont; font.pixelSize: tl.card.px(12)
            }
        }
    }
}
