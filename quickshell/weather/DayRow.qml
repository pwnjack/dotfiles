import QtQuick

// One day: name, condition, chance of rain, and its low and high joined by a
// bar on the scale every row shares. Today's bar carries a dot at the
// temperature now.
Item {
    id: row
    required property var card
    required property var day
    readonly property int gap: card.px(8)
    height: card.px(30)

    Text {
        id: name
        anchors.verticalCenter: parent.verticalCenter
        width: row.card.px(46)
        text: row.day.label
        elide: Text.ElideRight
        color: row.card.foreground
        font.family: row.card.monoFont
        font.pixelSize: row.card.px(12.5)
    }
    Text {
        id: glyph
        anchors.left: name.right
        anchors.leftMargin: row.gap
        anchors.verticalCenter: parent.verticalCenter
        width: row.card.px(20)
        horizontalAlignment: Text.AlignHCenter
        text: row.day.glyph
        color: row.card.foreground
        font.family: row.card.monoFont
        font.pixelSize: row.card.px(16)
    }
    Text {
        id: rain
        objectName: "rain"
        anchors.left: glyph.right
        anchors.leftMargin: row.gap
        anchors.verticalCenter: parent.verticalCenter
        width: row.card.px(34)
        horizontalAlignment: Text.AlignRight
        text: row.day.rain
        color: row.card.accent
        font.family: row.card.monoFont
        font.pixelSize: row.card.px(11)
    }
    // Wide enough for "-10°" and, in Fahrenheit, "104°".
    Text {
        id: low
        anchors.left: rain.right
        anchors.leftMargin: row.gap
        anchors.verticalCenter: parent.verticalCenter
        width: row.card.px(32)
        horizontalAlignment: Text.AlignRight
        text: row.day.low
        color: row.card.dim
        font.family: row.card.monoFont
        font.pixelSize: row.card.px(12.5)
    }
    Text {
        id: high
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: row.card.px(32)
        horizontalAlignment: Text.AlignRight
        text: row.day.high
        color: row.card.foreground
        font.family: row.card.monoFont
        font.pixelSize: row.card.px(12.5)
    }
    Rectangle {
        id: track
        objectName: "track"
        anchors.left: low.right
        anchors.leftMargin: row.gap
        anchors.right: high.left
        anchors.rightMargin: row.gap
        anchors.verticalCenter: parent.verticalCenter
        height: row.card.px(5)
        radius: height / 2
        color: row.card.hairline
        Rectangle {
            objectName: "range"
            // Never shorter than a dot: a day whose low and high meet is still drawn.
            width: Math.max(parent.height, (row.day.to - row.day.from) * parent.width)
            x: Math.min(row.day.from * parent.width, parent.width - width)
            height: parent.height
            radius: height / 2
            color: row.card.accent
        }
        Rectangle {
            objectName: "dot"
            visible: row.day.dot >= 0
            width: row.card.px(10)
            height: width
            radius: width / 2
            // Centred on the temperature, and kept whole inside the track.
            x: Math.max(0, Math.min(parent.width - width, row.day.dot * parent.width - width / 2))
            anchors.verticalCenter: parent.verticalCenter
            color: row.card.foreground
            border.width: row.card.px(2)
            border.color: row.card.background
        }
    }
}
