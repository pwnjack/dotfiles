import QtQuick

// A tappable value (date or time). `active` when its picker is open.
Rectangle {
    id: pill
    required property var card
    property string text: ""
    property bool active: false
    property bool strikeout: false
    signal clicked()
    signal wheelStep(int steps)
    implicitWidth: label.implicitWidth + card.px(24)
    implicitHeight: card.px(30)
    radius: card.px(8)
    color: active ? Qt.rgba(card.c.accent.r, card.c.accent.g, card.c.accent.b, 0.30)
                  : Qt.rgba(card.c.foreground.r, card.c.foreground.g, card.c.foreground.b, hov.containsMouse ? 0.14 : 0.09)
    border.width: active ? 1 : 0
    border.color: card.c.accent
    activeFocusOnTab: true
    // Return is not taken here: it passes to the sheet, which adds a valid draft.
    Keys.onSpacePressed: event => { pill.clicked(); event.accepted = true; }
    Keys.onUpPressed: event => { pill.wheelStep(1); event.accepted = true; }
    Keys.onDownPressed: event => { pill.wheelStep(-1); event.accepted = true; }
    Text {
        id: label
        anchors.centerIn: parent
        text: pill.text
        font.strikeout: pill.strikeout
        color: pill.strikeout ? "#e0787a" : pill.card.c.foreground
        font.family: pill.card.c.monoFont
        font.pixelSize: pill.card.px(13)
    }
    MouseArea {
        id: hov
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: pill.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: pill.clicked()
        onWheel: wheel => pill.wheelStep(wheel.angleDelta.y > 0 ? 1 : -1)
    }
}
