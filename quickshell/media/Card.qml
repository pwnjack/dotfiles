pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import "model.mjs" as Model

// The media card. One translucent frame, the weather card's, whose height
// follows what there is to show: the track, then the seek row when the
// player reports a length, the transport buttons, and the chips when there
// are two players or more. Everything shown comes from Model; nothing here
// decides, and nothing here calls a player: the controller does.
FocusScope {
    id: card
    required property var controller

    function px(size) { return Math.round(size * controller.uiScale); }
    readonly property color background: controller.background
    readonly property color foreground: controller.foreground
    readonly property color accent: controller.accent
    readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.62)
    readonly property color hairline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
    readonly property string monoFont: controller.monoFont
    readonly property var info: Model.view({ player: controller.player, position: controller.position })
    // Apart from `info`: the chips follow the players alone, so choosing one
    // leaves the focus on it.
    readonly property var chips: Model.chips(controller.players)

    function step(delta) {
        if (info.seekable) controller.seek(Model.step(controller.position, delta, info.seconds));
    }

    Keys.onEscapePressed: controller.close()
    // Space is play or pause wherever the focus is; Return presses a button.
    Keys.onSpacePressed: if (info.canToggle) controller.toggle()
    Keys.onLeftPressed: step(-Model.STEP_SECONDS)
    Keys.onRightPressed: step(Model.STEP_SECONDS)

    width: px(372)
    height: frame.height

    component Press: Rectangle {
        id: press
        property int glyph
        property string name
        property int size: card.px(34)
        signal clicked()
        Accessible.role: Accessible.Button
        Accessible.name: name
        Accessible.onPressAction: if (enabled) clicked()
        width: size
        height: size
        radius: card.px(10)
        opacity: enabled ? 1 : 0.35
        color: Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, area.containsMouse ? 0.12 : 0.06)
        border.width: activeFocus ? 2 : 0
        border.color: card.accent
        activeFocusOnTab: enabled
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        Text {
            anchors.centerIn: parent
            text: String.fromCodePoint(press.glyph)
            Accessible.ignored: true
            color: card.foreground
            font.family: card.monoFont
            font.pixelSize: Math.round(press.size * 0.5)
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: press.clicked()
        }
    }

    Rectangle {
        id: frame
        width: parent.width
        height: content.implicitHeight + card.px(36)
        radius: card.px(18)
        color: Qt.rgba(card.background.r, card.background.g, card.background.b, 0.68)
        border.width: 1
        border.color: Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.22)
        clip: true

        // Clicks inside the card never reach the close-on-outside-click area.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons } // a11y: not a control

        Column {
            id: content
            x: card.px(18)
            y: card.px(18)
            width: parent.width - card.px(36)
            spacing: card.px(14)

            // Album art, and the track beside it.
            Item {
                width: parent.width
                height: cover.height
                Item {
                    id: cover
                    width: card.px(96)
                    height: width
                    Rectangle {
                        anchors.fill: parent
                        visible: !shown.visible
                        radius: card.px(8)
                        color: Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.06)
                        Text {
                            objectName: "placeholder"
                            anchors.centerIn: parent
                            // The bar's own note.
                            text: String.fromCodePoint(0xf075a)
                            Accessible.ignored: true
                            color: card.dim
                            font.family: card.monoFont
                            font.pixelSize: card.px(34)
                        }
                    }
                    Image {
                        id: picture
                        objectName: "art"
                        anchors.fill: parent
                        source: card.info.art
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: Math.ceil(cover.width * Screen.devicePixelRatio)
                        sourceSize.height: Math.ceil(cover.height * Screen.devicePixelRatio)
                        asynchronous: true
                        visible: false
                    }
                    Rectangle {
                        id: mask
                        anchors.fill: parent
                        radius: card.px(8)
                        color: "white"
                        layer.enabled: true
                        visible: false
                    }
                    MultiEffect {
                        id: shown
                        anchors.fill: parent
                        visible: picture.status === Image.Ready
                        source: picture
                        maskEnabled: true
                        maskSource: mask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }
                }
                Column {
                    anchors.left: cover.right
                    anchors.leftMargin: card.px(14)
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: card.px(4)
                    // Plain text throughout: a track name is arbitrary text
                    // and must never be read as markup.
                    Text {
                        objectName: "title"
                        width: parent.width
                        text: card.info.title
                        textFormat: Text.PlainText
                        color: card.foreground
                        font.family: card.monoFont
                        font.pixelSize: card.px(15)
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    Text {
                        objectName: "artist"
                        width: parent.width
                        visible: text !== ""
                        text: card.info.artist
                        textFormat: Text.PlainText
                        color: card.dim
                        font.family: card.monoFont
                        font.pixelSize: card.px(13)
                        elide: Text.ElideRight
                    }
                    Text {
                        objectName: "album"
                        width: parent.width
                        visible: text !== ""
                        text: card.info.album
                        textFormat: Text.PlainText
                        color: card.dim
                        font.family: card.monoFont
                        font.pixelSize: card.px(12)
                        elide: Text.ElideRight
                    }
                }
            }

            // Elapsed, the bar, the length. A press moves the thumb and the
            // release seeks: one request for one gesture.
            Item {
                id: seekRow
                objectName: "seekRow"
                // Where the pointer holds the thumb, 0..1; -1 when it is free.
                // A thumb held while the track changes is let go: its release
                // would seek a track nobody aimed at.
                property real held: -1
                readonly property string track: card.info.track
                onTrackChanged: held = -1
                readonly property real at: held >= 0 ? held : card.info.progress
                width: parent.width
                height: card.px(18)
                visible: card.info.seekRow
                Accessible.role: Accessible.Slider
                Accessible.name: "Seek, " + elapsed.text
                Accessible.ignored: !card.info.seekable
                Accessible.onIncreaseAction: if (enabled) card.step(Model.STEP_SECONDS)
                Accessible.onDecreaseAction: if (enabled) card.step(-Model.STEP_SECONDS)
                Text {
                    id: elapsed
                    objectName: "elapsed"
                    anchors.verticalCenter: parent.verticalCenter
                    text: seekRow.held >= 0 ? Model.time(Model.seek(seekRow.held, card.info.seconds)) : card.info.elapsed
                    color: card.dim
                    font.family: card.monoFont
                    font.pixelSize: card.px(11)
                }
                Text {
                    id: total
                    objectName: "length"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.info.length
                    color: card.dim
                    font.family: card.monoFont
                    font.pixelSize: card.px(11)
                }
                Rectangle {
                    id: track
                    anchors.left: elapsed.right
                    anchors.leftMargin: card.px(10)
                    anchors.right: total.left
                    anchors.rightMargin: card.px(10)
                    anchors.verticalCenter: parent.verticalCenter
                    height: card.px(4)
                    radius: height / 2
                    color: Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.16)
                    Rectangle {
                        objectName: "played"
                        width: parent.width * seekRow.at
                        height: parent.height
                        radius: parent.radius
                        color: card.accent
                    }
                    Rectangle {
                        objectName: "thumb"
                        visible: card.info.seekable
                        width: card.px(10)
                        height: width
                        radius: width / 2
                        x: parent.width * seekRow.at - width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: card.foreground
                    }
                }
                MouseArea {
                    objectName: "seekArea"
                    anchors.left: track.left
                    anchors.right: track.right
                    height: parent.height
                    enabled: card.info.seekable
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    function fraction(x) { return Math.max(0, Math.min(1, x / width)); }
                    onPressed: mouse => seekRow.held = fraction(mouse.x)
                    onPositionChanged: mouse => { if (pressed && seekRow.held >= 0) seekRow.held = fraction(mouse.x); }
                    onReleased: {
                        if (seekRow.held >= 0) card.controller.seek(Model.seek(seekRow.held, card.info.seconds));
                        seekRow.held = -1;
                    }
                    onCanceled: seekRow.held = -1
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: card.px(18)
                Press {
                    objectName: "previous"
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: 0xf04ae
                    name: "Previous"
                    enabled: card.info.canPrevious
                    onClicked: card.controller.previous()
                }
                Press {
                    objectName: "toggle"
                    size: card.px(42)
                    glyph: card.info.playing ? 0xf03e4 : 0xf040a
                    name: card.info.playing ? "Pause" : "Play"
                    enabled: card.info.canToggle
                    onClicked: card.controller.toggle()
                }
                Press {
                    objectName: "next"
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: 0xf04ad
                    name: "Next"
                    enabled: card.info.canNext
                    onClicked: card.controller.next()
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: card.hairline
                visible: chipRow.visible
            }
            // One chip per player; the one shown is in the accent colour.
            Flow {
                id: chipRow
                objectName: "chips"
                width: parent.width
                spacing: card.px(6)
                visible: chipList.count > 0
                Repeater {
                    id: chipList
                    objectName: "chipList"
                    model: card.chips
                    Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool current: modelData.player === card.controller.player
                        width: Math.min(chipRow.width, label.implicitWidth + card.px(20))
                        height: card.px(26)
                        radius: card.px(8)
                        color: chip.current ? Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.22)
                            : Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, hover.containsMouse ? 0.12 : 0.06)
                        border.width: activeFocus ? 2 : 0
                        border.color: card.accent
                        activeFocusOnTab: true
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: modelData.label
                        Accessible.checkable: true
                        Accessible.checked: current
                        Accessible.onPressAction: if (enabled) card.controller.show(modelData.player)
                        Keys.onReturnPressed: card.controller.show(modelData.player)
                        Keys.onEnterPressed: card.controller.show(modelData.player)
                        Text {
                            id: label
                            objectName: "chipLabel"
                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, parent.width - card.px(20))
                            text: chip.modelData.label
                            Accessible.ignored: true
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: chip.current ? card.accent : card.dim
                            font.family: card.monoFont
                            font.pixelSize: card.px(12)
                        }
                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.controller.show(chip.modelData.player)
                        }
                    }
                }
            }
        }
    }
}
