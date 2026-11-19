pragma ComponentBehavior: Bound
import QtQuick
import "model.mjs" as Model

// The weather card. One translucent frame, the update card's, whose height
// follows what there is to show: the header alone while there is no
// forecast, then the hours, the days and the footer. Everything shown comes
// from Model.view; nothing here decides.
FocusScope {
    id: card
    required property var controller

    function px(size) { return Math.round(size * controller.uiScale); }
    readonly property color background: controller.background
    readonly property color foreground: controller.foreground
    readonly property color accent: controller.accent
    readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.62)
    readonly property color hairline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
    // Fixed amber keeps warnings distinct from the wallpaper accent.
    readonly property color warn: "#e3a857"
    readonly property string monoFont: controller.monoFont
    readonly property var info: Model.view({
        forecast: controller.forecast, now: controller.clock, clock: controller.clockMode,
        am: controller.locale.amText, pm: controller.locale.pmText,
        // Locale.dayName counts from Sunday, as the model expects.
        dayNames: [0, 1, 2, 3, 4, 5, 6].map(day => controller.locale.dayName(day, Locale.ShortFormat)),
        phase: controller.phase, reason: controller.reason
    })

    Keys.onEscapePressed: controller.close()

    width: px(372)
    height: frame.height

    Rectangle {
        id: frame
        width: parent.width
        height: content.implicitHeight + card.px(36)
        // Eases when a forecast arrives in an open card. Not while it is
        // closed: the card must open at its size, not grow into it.
        Behavior on height {
            enabled: card.controller.opened
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
        }
        radius: card.px(18)
        color: Qt.rgba(card.background.r, card.background.g, card.background.b, 0.68)
        border.width: 1
        border.color: Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.22)
        clip: true

        // Clicks inside the card never reach the close-on-outside-click area.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        Column {
            id: content
            x: card.px(18)
            y: card.px(18)
            width: parent.width - card.px(36)
            spacing: card.px(14)

            // Badge, condition and place, and the temperature now.
            Item {
                width: parent.width
                height: Math.max(card.px(40), words.implicitHeight)
                Rectangle {
                    id: badge
                    anchors.verticalCenter: parent.verticalCenter
                    width: card.px(40)
                    height: width
                    radius: card.px(12)
                    color: Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.22)
                    Text {
                        objectName: "glyph"
                        anchors.centerIn: parent
                        text: card.info.glyph
                        color: card.accent
                        font.family: card.monoFont
                        font.pixelSize: card.px(20)
                    }
                }
                Text {
                    id: now
                    objectName: "temp"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.info.temp
                    color: card.foreground
                    font.family: card.monoFont
                    font.pixelSize: card.px(30)
                    font.weight: Font.Medium
                }
                Column {
                    id: words
                    anchors.left: badge.right
                    anchors.leftMargin: card.px(12)
                    anchors.right: now.left
                    anchors.rightMargin: now.text ? card.px(12) : 0
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: card.px(2)
                    Text {
                        objectName: "title"
                        width: parent.width
                        text: card.info.title
                        color: card.foreground
                        font.family: card.monoFont
                        font.pixelSize: card.px(15)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    // The place gives way to what follows it: "City, Country"
                    // when that fits, the city alone when it does not, and a
                    // cut city last. How it feels is never cut. A reason with
                    // no place before it has the whole width and two lines.
                    // 12 px, a pixel under the update card's subtitle: at 13
                    // an eleven-letter "City, Country" no longer fits beside a
                    // two-digit temperature.
                    Row {
                        id: under
                        readonly property real room: Math.max(0, width - dot.implicitWidth - detail.implicitWidth)
                        width: parent.width
                        visible: place.text !== "" || detail.text !== ""
                        TextMetrics { id: whole; font: place.font; text: card.info.place }
                        Text {
                            id: place
                            objectName: "place"
                            visible: text !== ""
                            width: Math.min(implicitWidth, under.room)
                            text: whole.advanceWidth <= under.room ? card.info.place : card.info.city
                            elide: Text.ElideRight
                            color: card.dim
                            font.family: card.monoFont
                            font.pixelSize: card.px(12)
                        }
                        Text {
                            id: dot
                            visible: place.visible && detail.visible
                            text: " · "
                            color: card.dim
                            font.family: card.monoFont
                            font.pixelSize: card.px(12)
                        }
                        Text {
                            id: detail
                            objectName: "detail"
                            visible: text !== ""
                            width: place.visible ? implicitWidth : parent.width
                            text: card.info.detail
                            wrapMode: place.visible ? Text.NoWrap : Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            color: card.dim
                            font.family: card.monoFont
                            font.pixelSize: card.px(12)
                        }
                    }
                }
            }

            HourStrip {
                objectName: "hours"
                card: card
                width: parent.width
                visible: card.info.hours.length > 0
                hours: card.info.hours
            }

            Rectangle {
                width: parent.width
                height: 1
                color: card.hairline
                visible: days.count > 0
            }
            Column {
                width: parent.width
                visible: days.count > 0
                Repeater {
                    id: days
                    objectName: "days"
                    model: card.info.days
                    DayRow {
                        required property var modelData
                        card: card
                        width: content.width
                        day: modelData
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: card.hairline
                visible: footer.visible
            }
            // Sun times left, the forecast's age right; on two lines when
            // both do not fit (the offline note is the long one).
            Item {
                id: footer
                readonly property bool stacked: sun.text !== "" && note.text !== ""
                    && sun.implicitWidth + note.implicitWidth + card.px(8) > width
                width: parent.width
                visible: sun.text !== "" || note.text !== ""
                height: stacked ? sun.implicitHeight + card.px(4) + note.implicitHeight
                    : Math.max(sun.implicitHeight, note.implicitHeight)
                Text {
                    id: sun
                    objectName: "sun"
                    text: card.info.sun
                    color: card.dim
                    font.family: card.monoFont
                    font.pixelSize: card.px(11)
                }
                Text {
                    id: note
                    objectName: "note"
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    text: card.info.note
                    color: card.info.warn ? card.warn : card.dim
                    font.family: card.monoFont
                    font.pixelSize: card.px(11)
                }
            }
        }
    }
}
