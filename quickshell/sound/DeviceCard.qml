pragma ComponentBehavior: Bound
import QtQuick

// The Output or Input card on Devices: the current default's label (› opens
// the picker, even when there is no default), its volume and mute, the
// headset battery chip, and on Input the live level meter.
Rectangle {
    id: card
    required property var popover
    required property string kind       // output | input
    readonly property var controller: popover.controller
    readonly property var device: kind === "output" ? controller.output : controller.input
    readonly property bool live: controller.ready && !!device
    objectName: kind + "Card"
    implicitHeight: column.implicitHeight + popover.px(16)
    radius: popover.px(13)
    color: Qt.rgba(popover.foreground.r, popover.foreground.g, popover.foreground.b, 0.05)

    Column {
        id: column
        x: card.popover.px(10)
        y: card.popover.px(8)
        width: parent.width - card.popover.px(20)
        spacing: card.popover.px(6)

        Item {
            width: parent.width
            height: heading.implicitHeight
            Column {
                id: heading
                width: parent.width - chevron.width - card.popover.px(8)
                Text {
                    objectName: card.kind + "Label"
                    width: Math.min(implicitWidth, parent.width)
                    elide: Text.ElideRight
                    text: !card.controller.ready ? "Sound server not running"
                        : card.device ? card.device.label
                        : card.kind === "output" ? "No output" : "No input"
                    color: card.live ? card.popover.foreground : card.popover.dim
                    font.family: card.popover.monoFont
                    font.pixelSize: card.popover.px(13)
                    font.weight: Font.Medium
                }
                Text {
                    text: card.kind === "output" ? "Output" : "Input"
                    color: card.popover.dim
                    font.family: card.popover.monoFont
                    font.pixelSize: card.popover.px(11)
                }
            }
            Text {
                id: chevron
                objectName: card.kind + "Chevron"
                visible: card.controller.ready
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                color: picking.containsMouse ? card.popover.foreground : card.popover.dim
                font.family: card.popover.monoFont
                font.pixelSize: card.popover.px(18)
            }
            MouseArea {
                id: picking
                anchors.fill: parent
                enabled: card.controller.ready
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: card.controller.openPicker(card.kind)
            }
        }

        Item {
            visible: card.live
            width: parent.width
            height: slider.implicitHeight
            Text {
                id: mute
                objectName: card.kind + "Mute"
                width: card.popover.px(22)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                // md-volume_high / md-volume_off, md-microphone / md-microphone_off
                text: String.fromCodePoint(card.kind === "output"
                    ? (card.live && card.device.muted ? 0xf0581 : 0xf057e)
                    : (card.live && card.device.muted ? 0xf036d : 0xf036c))
                color: muteArea.containsMouse ? card.popover.foreground : card.popover.dim
                font.family: card.popover.iconFont
                font.pixelSize: card.popover.px(15)
                MouseArea {
                    id: muteArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.controller.setMuted(card.device.key, !card.device.muted)
                }
            }
            VolumeSlider {
                id: slider
                objectName: card.kind + "Slider"
                popover: card.popover
                anchors.left: mute.right
                anchors.leftMargin: card.popover.px(6)
                anchors.right: parent.right
                // Input above 100 % is software gain, as Settings allowed.
                max: card.kind === "output" ? 1 : 1.5
                key: card.live ? card.device.key : ""
                value: card.live ? card.device.volume : 0
                muted: card.live && card.device.muted
                onCommit: (key, v) => card.controller.setVolume(key, v)
            }
        }

        Row {
            // The chips' own conditions: their `visible` reads false while this row's is.
            visible: chip.known || virtualChip.shown
            spacing: card.popover.px(6)
            Rectangle {
                id: chip
                objectName: card.kind + "Battery"
                readonly property bool known: card.live && typeof card.device.battery === "number"
                readonly property string text: known ? card.device.battery + " %" : ""
                visible: known
                width: chipRow.implicitWidth + card.popover.px(14)
                height: chipRow.implicitHeight + card.popover.px(4)
                radius: height / 2
                color: Qt.rgba(card.popover.foreground.r, card.popover.foreground.g, card.popover.foreground.b, 0.08)
                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: card.popover.px(4)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: String.fromCodePoint(card.popover.batteryGlyph(chip.known ? card.device.battery : 0))
                        color: card.popover.dim
                        font.family: card.popover.iconFont
                        font.pixelSize: card.popover.px(11)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.text
                        color: card.popover.dim
                        font.family: card.popover.monoFont
                        font.pixelSize: card.popover.px(11)
                        font.features: ({ "tnum": 1 })
                    }
                }
            }
            // A virtual default (set elsewhere, e.g. wpctl) still shows and is controlled here.
            Rectangle {
                id: virtualChip
                objectName: card.kind + "Virtual"
                readonly property string text: "Virtual"
                readonly property bool shown: card.live && card.device.virtual === true
                visible: shown
                width: virtualText.implicitWidth + card.popover.px(14)
                height: virtualText.implicitHeight + card.popover.px(4)
                radius: height / 2
                color: Qt.rgba(card.popover.foreground.r, card.popover.foreground.g, card.popover.foreground.b, 0.08)
                Text {
                    id: virtualText
                    anchors.centerIn: parent
                    text: virtualChip.text
                    color: card.popover.dim
                    font.family: card.popover.monoFont
                    font.pixelSize: card.popover.px(11)
                }
            }
        }

        Rectangle {
            objectName: "meter"
            visible: card.live && card.kind === "input"
            // Under the slider's track: mute (22) + gap (6) + half a handle (7)
            // in, percentage (42) + gap (8) + half a handle out.
            x: card.popover.px(35)
            width: parent.width - card.popover.px(92)
            height: card.popover.px(3)
            radius: height / 2
            color: Qt.rgba(card.popover.foreground.r, card.popover.foreground.g, card.popover.foreground.b, 0.14)
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, card.controller.meter))
                height: parent.height
                radius: parent.radius
                color: card.popover.accent
                Behavior on width { NumberAnimation { duration: 80 } }
            }
        }
    }
}
