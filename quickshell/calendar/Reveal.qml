import QtQuick

// A section that opens by growing to its content's height and closes by
// shrinking to nothing, clipped as it goes, so what is below slides instead of
// jumping. It stays visible while it closes; `open` is the state it is heading to.
Item {
    id: reveal
    required property var card
    property bool open: false
    property real padding: 0
    default property alias content: holder.data
    readonly property real fullHeight: holder.childrenRect.height + 2 * padding
    implicitHeight: open ? fullHeight : 0
    Behavior on implicitHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    visible: open || implicitHeight > 0
    clip: true
    Item {
        id: holder
        x: reveal.padding; y: reveal.padding
        width: reveal.width - 2 * reveal.padding
        height: childrenRect.height
        opacity: reveal.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
}
