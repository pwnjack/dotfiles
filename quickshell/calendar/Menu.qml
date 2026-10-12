pragma ComponentBehavior: Bound
import QtQuick

// A dropdown of choices ({value, label, color?}) with a tick on `current`. It
// floats over the sheet rather than pushing its rows apart; the sheet places it
// beside its pill (Sheet.placeMenu) and owns `open`. Past `maxHeight` its list
// scrolls. While open it keeps the keys: ↑ ↓ move, Return or Space choose, Tab
// stays put, and Esc passes on to the sheet, which closes it.
Rectangle {
    id: menu
    required property var card
    property var items: []
    property string current: ""
    property bool open: false
    property bool above: false          // opened above its pill: it grows from its bottom edge
    property real maxHeight: Infinity
    property real maxWidth: Infinity
    property int hi: -1                 // the highlighted row, by pointer or keys
    // Where the sheet puts it (Sheet.placeMenu): the pill's right edge and the edge to grow
    // from, within a visible band. x and y follow the menu's own size from these.
    property real anchorRight: 0
    property real anchorY: 0
    property real bandTop: 0
    property real bandBottom: Infinity
    x: Math.max(0, anchorRight - width)
    y: Math.max(bandTop, Math.min(bandBottom - height, above ? anchorY - height : anchorY))
    signal chosen(string value)
    readonly property real pad: card.px(5)
    readonly property real rowHeight: card.px(28)
    // As wide as the longest label (with its dot and tick), within maxWidth; longer labels elide.
    FontMetrics { id: metrics; font.family: menu.card.c.monoFont; font.pixelSize: menu.card.px(13) }
    readonly property real labelWidth: items.reduce((w, i) => Math.max(w, metrics.advanceWidth(i.label)), 0)
    width: Math.min(maxWidth, Math.max(card.px(180), labelWidth + card.px(9 + 17 + 8 + 14 + 9) + 2 * pad))
    height: Math.min(maxHeight, items.length * rowHeight + 2 * pad)
    radius: card.px(12)
    z: 40
    color: Qt.rgba(card.c.background.r * 1.6, card.c.background.g * 1.6, card.c.background.b * 1.6, 0.98)
    border.width: 1
    border.color: Qt.rgba(card.c.foreground.r, card.c.foreground.g, card.c.foreground.b, 0.18)
    opacity: open ? 1 : 0
    scale: open ? 1 : 0.96
    transformOrigin: above ? Item.BottomRight : Item.TopRight
    visible: opacity > 0
    enabled: open
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    onOpenChanged: if (open) {
        hi = Math.max(0, items.findIndex(i => i.value === current));
        list.positionViewAtIndex(hi, ListView.Contain);
        forceActiveFocus();
    }
    function move(step) { hi = Math.max(0, Math.min(items.length - 1, hi + step)); list.positionViewAtIndex(hi, ListView.Contain); }
    function pick() { if (hi >= 0 && hi < items.length) chosen(items[hi].value); }
    Keys.onUpPressed: event => { move(-1); event.accepted = true; }
    Keys.onDownPressed: event => { move(1); event.accepted = true; }
    Keys.onReturnPressed: event => { pick(); event.accepted = true; }
    Keys.onEnterPressed: event => { pick(); event.accepted = true; }
    Keys.onSpacePressed: event => { pick(); event.accepted = true; }
    // Focus never leaves an open menu by Tab either way: Return elsewhere would add the event.
    Keys.onTabPressed: event => { event.accepted = true; }
    Keys.onBacktabPressed: event => { event.accepted = true; }
    ListView {
        id: list
        anchors.fill: parent
        anchors.margins: menu.pad
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        model: menu.items
        delegate: Rectangle {
            id: item
            required property var modelData
            required property int index
            objectName: "menuItem" + index
            width: ListView.view.width
            height: menu.rowHeight
            radius: menu.card.px(7)
            color: item.index === menu.hi ? Qt.rgba(menu.card.c.accent.r, menu.card.c.accent.g, menu.card.c.accent.b, 0.28) : "transparent"
            Rectangle {
                id: dot
                visible: !!item.modelData.color
                x: menu.card.px(9)
                anchors.verticalCenter: parent.verticalCenter
                width: menu.card.px(9); height: width; radius: width / 2
                color: item.modelData.color || "transparent"
            }
            Text {
                x: dot.visible ? dot.x + dot.width + menu.card.px(8) : menu.card.px(9)
                width: tick.x - x - menu.card.px(8)
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: item.modelData.label
                color: menu.card.c.foreground
                font.family: menu.card.c.monoFont
                font.pixelSize: menu.card.px(13)
            }
            Text {
                id: tick
                objectName: "tick" + item.index
                visible: item.modelData.value === menu.current
                x: parent.width - menu.card.px(9) - width
                anchors.verticalCenter: parent.verticalCenter
                text: "✓"
                color: menu.card.c.accent
                font.pixelSize: menu.card.px(13)
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) menu.hi = item.index
                onClicked: menu.chosen(item.modelData.value)
            }
        }
    }
}
