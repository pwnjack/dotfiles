pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "model.mjs" as Model

// The capture strip (docs/capture.md): a segmented mode pill centred above
// one row of controls. Every control shows its current value; the controller
// (shell.qml) owns the state and the option files.
// The option group is as wide as the wider mode and the action button as wide
// as its widest label, so switching tabs or a running timer moves nothing.
FocusScope {
    id: strip
    required property var controller

    function px(size) { return Math.round(size * controller.uiScale); }
    readonly property color background: controller.background
    readonly property color foreground: controller.foreground
    readonly property color accent: controller.accent
    readonly property color accentInk: controller.accentInk
    readonly property string monoFont: controller.monoFont
    readonly property color hairline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.16)
    readonly property color surface: Qt.rgba(background.r, background.g, background.b, 0.94)
    // Fixed red: the bar's documented alert exception, so the Record tab, the
    // Record button and the Waybar timer are one colour.
    readonly property color red: "#ff5555"
    readonly property color redInk: "#05090c"
    // Not "state": Item already has a state property (its States).
    readonly property var current: controller.state
    readonly property string mode: current.mode
    readonly property var act: Model.action(current, controller.status)

    readonly property var targets: ({
        screen: { glyph: 0xF0379, label: "Screen", tip: "The focused monitor" },
        window: { glyph: 0xF05AF, label: "Window",
            tip: mode === "record" ? "Click a window. The recording keeps that rectangle; it does not follow the window."
                                   : "Click a window" },
        region: { glyph: 0xF0A6C, label: "Region", tip: "Drag a rectangle" }
    })

    implicitWidth: panel.width
    implicitHeight: tabs.height + px(8) + panel.height
    width: implicitWidth
    height: implicitHeight

    // The mockup's entrance: fade over 180 ms while rising 8 px over 220 ms.
    signal gone()
    property real fade: 0
    property real lift: 0
    opacity: fade
    transform: Translate { y: strip.px(8) * (1 - strip.lift) }
    function appear() {
        leave.stop();
        enter.start();
        forceActiveFocus();
    }
    function disappear() {
        enter.stop();
        leave.start();
    }
    ParallelAnimation {
        id: enter
        NumberAnimation { target: strip; property: "fade"; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: strip; property: "lift"; to: 1; duration: 220; easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: leave
        NumberAnimation { target: strip; property: "fade"; to: 0; duration: 140; easing.type: Easing.InCubic }
        NumberAnimation { target: strip; property: "lift"; to: 0; duration: 140; easing.type: Easing.InCubic }
        onFinished: strip.gone()
    }

    // Tab and Shift+Tab step through the modes, arrows move the target, Return
    // runs, Esc closes.
    // No letter shortcuts for the toggles.
    // Returns whether the key was one the strip handles.
    function handleKey(key, autoRepeat) {
        const names = {};
        names[Qt.Key_Tab] = "Tab";
        names[Qt.Key_Backtab] = "Backtab";
        names[Qt.Key_Left] = "Left";
        names[Qt.Key_Right] = "Right";
        names[Qt.Key_Return] = "Return";
        names[Qt.Key_Enter] = "Return";
        names[Qt.Key_Escape] = "Escape";
        const name = names[key];
        if (!name) return false;
        // A held Return/Enter/Escape/Tab must act once; arrows may repeat.
        if (autoRepeat && name !== "Left" && name !== "Right") return true;
        controller.key(name);
        return true;
    }
    Keys.onPressed: event => { event.accepted = strip.handleKey(event.key, event.isAutoRepeat); }

    Rectangle {
        id: tabs
        anchors.horizontalCenter: parent.horizontalCenter
        width: tabRow.implicitWidth + strip.px(6)
        height: tabRow.implicitHeight + strip.px(6)
        radius: strip.px(11)
        color: strip.surface
        border.width: 1
        border.color: strip.hairline
        // A click on the pill itself must not reach the window's
        // click-outside-closes area; the space beside it must.
        MouseArea { anchors.fill: parent }
        Row {
            id: tabRow
            anchors.centerIn: parent
            spacing: strip.px(2)
            Repeater {
                model: [{ mode: "screenshot", glyph: 0xF0100, label: "Screenshot" },
                        { mode: "text", glyph: 0xF113D, label: "Text" },
                        { mode: "record", glyph: 0xF0567, label: "Record" }]
                delegate: Rectangle {
                    id: tab
                    required property var modelData
                    readonly property bool active: strip.mode === modelData.mode
                    readonly property color ink: active ? (modelData.mode === "record" ? strip.redInk : strip.accentInk) : strip.foreground
                    objectName: "tab-" + modelData.mode
                    width: tabContent.implicitWidth + strip.px(28)
                    height: tabContent.implicitHeight + strip.px(10)
                    radius: strip.px(8)
                    color: active ? (modelData.mode === "record" ? strip.red : strip.accent) : "transparent"
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: modelData.label
                    Accessible.checkable: true
                    Accessible.checked: active
                    Row {
                        id: tabContent
                        anchors.centerIn: parent
                        spacing: strip.px(7)
                        opacity: tab.active ? 1 : 0.75
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: String.fromCodePoint(tab.modelData.glyph)
                            color: tab.ink
                            font.family: strip.monoFont
                            font.pixelSize: strip.px(14)
                        }
                        Text {
                            objectName: "label"
                            anchors.verticalCenter: parent.verticalCenter
                            text: tab.modelData.label
                            color: tab.ink
                            elide: Text.ElideRight
                            font.family: strip.monoFont
                            font.pixelSize: strip.px(12.5)
                            font.weight: tab.active ? Font.DemiBold : Font.Normal
                        }
                    }
                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: strip.controller.setMode(tab.modelData.mode)
                    }
                    ToolTip {
                        popupType: Popup.Item
                        visible: tabMouse.containsMouse
                        delay: 600
                        text: tab.modelData.label + " (Tab)"
                        contentItem: Text {
                            text: tab.modelData.label + " (Tab)"
                            color: strip.foreground
                            font.family: strip.monoFont
                            font.pixelSize: strip.px(12)
                        }
                        background: Rectangle {
                            color: strip.background
                            radius: strip.px(6)
                            border.color: strip.hairline
                        }
                    }
                }
            }
        }
    }

    component Separator: Item {
        width: strip.px(13)
        height: strip.px(62)
        Rectangle {
            anchors.centerIn: parent
            width: 1
            height: parent.height - 2 * strip.px(4)
            color: Qt.rgba(strip.foreground.r, strip.foreground.g, strip.foreground.b, 0.14)
        }
    }

    Rectangle {
        id: panel
        y: tabs.height + strip.px(8)
        width: row.implicitWidth + 2 * strip.px(8)
        height: strip.px(62) + 2 * strip.px(8)
        radius: strip.px(14)
        color: strip.surface
        border.width: 1
        border.color: strip.hairline
        // As for the pill: swallow clicks on the panel only.
        MouseArea { anchors.fill: parent }

        Row {
            id: row
            x: strip.px(8)
            y: strip.px(8)
            spacing: strip.px(4)

            // Text has no target: the row is hidden but keeps its width, so
            // switching tabs moves nothing.
            Item {
                width: targetRow.implicitWidth
                height: strip.px(62)
                Row {
                    id: targetRow
                    visible: strip.mode !== "text"
                    spacing: strip.px(4)
                    Repeater {
                        model: Model.TARGETS
                        delegate: StripButton {
                            required property string modelData
                            strip: strip
                            objectName: "target-" + modelData
                            baseWidth: 62
                            glyph: strip.targets[modelData].glyph
                            label: strip.targets[modelData].label
                            tip: strip.targets[modelData].tip
                            on: strip.current[Model.targetKey(strip.mode)] === modelData
                            onClicked: strip.controller.setTarget(modelData)
                        }
                    }
                }
            }
            Separator {}
            Item {
                width: Math.max(shotOptions.implicitWidth, recOptions.implicitWidth)
                height: strip.px(62)
                Row {
                    id: shotOptions
                    // Text shares the screenshot's delay and freeze; only
                    // Annotate is a screenshot's alone.
                    visible: strip.mode !== "record"
                    spacing: strip.px(4)
                    StripButton {
                        strip: strip; objectName: "shot-delay"; glyph: 0xF051B
                        label: Model.delayLabel(strip.current.delay); on: strip.current.delay > 0
                        tip: "Wait before capturing. Click: Off, 3, 5, 10 s"
                        onClicked: strip.controller.cycleDelay()
                    }
                    StripButton {
                        strip: strip; objectName: "screenshot-freeze"; glyph: 0xF0717
                        label: "Freeze"; on: strip.current.freeze
                        tip: "Freeze the screen while you select"
                        onClicked: strip.controller.toggleOption("freeze")
                    }
                    // Text hides Annotate but keeps its slot, so the row,
                    // and with it the strip, keeps its width.
                    Item {
                        width: annotate.width
                        height: annotate.height
                        StripButton {
                            id: annotate
                            visible: strip.mode === "screenshot"
                            strip: strip; objectName: "screenshot-annotate"; glyph: 0xF03EB; baseWidth: 60
                            label: "Annotate"; on: strip.current.annotate
                            tip: "Open the shot in swappy to mark it up"
                            onClicked: strip.controller.toggleOption("annotate")
                        }
                    }
                }
                Row {
                    id: recOptions
                    visible: strip.mode === "record"
                    spacing: strip.px(4)
                    StripButton {
                        strip: strip; objectName: "rec-delay"; glyph: 0xF051B
                        label: Model.delayLabel(strip.current.delay); on: strip.current.delay > 0
                        tip: "Count down in the bar before recording. Click: Off, 3, 5, 10 s"
                        onClicked: strip.controller.cycleDelay()
                    }
                    StripButton {
                        strip: strip; objectName: "record-audio"; glyph: 0xF057E
                        label: "Audio"; on: strip.current.audio
                        tip: "Record desktop audio"
                        onClicked: strip.controller.toggleOption("audio")
                    }
                    StripButton {
                        strip: strip; objectName: "record-mic"; glyph: strip.current.mic ? 0xF036C : 0xF036D
                        label: "Mic"; on: strip.current.mic
                        tip: "Record the microphone"
                        onClicked: strip.controller.toggleOption("mic")
                    }
                }
            }
            Separator {}
            Rectangle {
                id: actionButton
                objectName: "action"
                readonly property bool red: strip.act.kind !== "capture"
                readonly property color ink: red ? strip.redInk : strip.accentInk
                width: strip.px(32) + glyphMetrics.advanceWidth + strip.px(8) + widest.advanceWidth
                height: strip.px(62)
                radius: strip.px(9)
                color: (red ? strip.red : strip.accent)
                Accessible.role: Accessible.Button
                Accessible.name: strip.act.label
                scale: actionMouse.pressed ? 0.97 : 1
                Behavior on scale { NumberAnimation { duration: 100 } }
                TextMetrics { id: widest; font: actionLabel.font; text: Model.WIDEST_ACTION_LABEL }
                TextMetrics { id: glyphMetrics; font.family: strip.monoFont; font.pixelSize: strip.px(16); text: String.fromCodePoint(0xF044A) }
                Row {
                    anchors.centerIn: parent
                    spacing: strip.px(8)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: String.fromCodePoint(strip.act.glyph)
                        color: actionButton.ink
                        font.family: strip.monoFont
                        font.pixelSize: strip.px(16)
                    }
                    Text {
                        id: actionLabel
                        objectName: "label"
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, widest.advanceWidth + 1)
                        elide: Text.ElideRight
                        text: strip.act.label
                        color: actionButton.ink
                        font.family: strip.monoFont
                        font.pixelSize: strip.px(13)
                        font.weight: Font.DemiBold
                    }
                }
                MouseArea {
                    id: actionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: strip.controller.run()
                }
                ToolTip {
                    id: actionTip
                    objectName: "action-tip"
                    popupType: Popup.Item
                    visible: actionMouse.containsMouse
                    delay: 600
                    readonly property string tip: strip.mode === "screenshot" ? "Take the screenshot (Return)"
                        : strip.mode === "text" ? "Drag a region to copy its text or QR code (Return)"
                        : actionButton.red ? "Stop and save (Return)" : "Start recording (Return)"
                    text: tip
                    contentItem: Text {
                        // contentItem is reparented to the popup: name the tip, not parent.
                        text: actionTip.text
                        color: strip.foreground
                        font.family: strip.monoFont
                        font.pixelSize: strip.px(12)
                    }
                    background: Rectangle {
                        color: strip.background
                        radius: strip.px(6)
                        border.color: strip.hairline
                    }
                }
            }
            StripButton {
                strip: strip
                objectName: "close"
                glyph: 0xF0156
                baseWidth: 34
                opacity: 0.6
                tip: "Close (Esc)"
                onClicked: strip.controller.close()
            }
        }
    }
}
