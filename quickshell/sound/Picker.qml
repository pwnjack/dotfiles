pragma ComponentBehavior: Bound
import QtQuick

// The Output or Input picker, slid in over Devices. A radio list of the shown
// devices; hidden ones fold into "Show N hidden" and appear inline, dimmed and
// still selectable. Rows are keyed, so a PipeWire change mid-click keeps them.
Column {
    id: picker
    required property var popover
    readonly property var controller: popover.controller
    objectName: "picker"
    // The last kind opened: it stays drawn while the picker slides away.
    property string kind: "output"
    property bool revealed: false
    // 0 hidden, 1 in place; the popover slides both views by it.
    property real shownFraction: controller.picker !== "" ? 1 : 0
    Behavior on shownFraction { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    readonly property var list: (kind === "output" ? controller.outputs : controller.inputs) || ({ shown: [], hidden: [] })
    readonly property var shownByKey: popover.byKey(list.shown)
    readonly property var hiddenByKey: popover.byKey(list.hidden)
    spacing: popover.px(6)

    function sync() {
        popover.syncKeys(shownModel, list.shown);
        popover.syncKeys(hiddenModel, list.hidden);
    }
    onListChanged: sync()
    Component.onCompleted: sync()
    Connections {
        target: picker.controller
        function onPickerChanged() {
            if (picker.controller.picker === "") return;
            picker.kind = picker.controller.picker;
            picker.revealed = false;
        }
    }
    ListModel { id: shownModel }
    ListModel { id: hiddenModel }

    component DeviceRow: Rectangle {
        id: row
        required property string key
        required property var devices
        readonly property var device: devices[key] || picker.popover.noDevice
        readonly property bool checked: device.current
        width: picker.width
        height: picker.popover.px(34)
        radius: picker.popover.px(11)
        activeFocusOnTab: visible
        color: checked ? Qt.rgba(picker.popover.accent.r, picker.popover.accent.g, picker.popover.accent.b, 0.2)
             : area.containsMouse ? Qt.rgba(picker.popover.foreground.r, picker.popover.foreground.g, picker.popover.foreground.b, 0.06)
             : "transparent"
        border.width: activeFocus ? 2 : 0
        border.color: picker.popover.accent
        function choose() { picker.controller.choose(picker.kind, device.key); }
        Keys.onReturnPressed: choose()
        Keys.onEnterPressed: choose()
        Keys.onSpacePressed: choose()

        Rectangle {
            id: radio
            x: picker.popover.px(10)
            anchors.verticalCenter: parent.verticalCenter
            width: picker.popover.px(14)
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: row.checked ? picker.popover.accent : picker.popover.dim
            Rectangle {
                visible: row.checked
                anchors.centerIn: parent
                width: parent.width * 0.45
                height: width
                radius: width / 2
                color: picker.popover.accent
            }
        }
        Text {
            anchors.left: radio.right
            anchors.leftMargin: picker.popover.px(10)
            anchors.right: chip.visible ? chip.left : parent.right
            anchors.rightMargin: picker.popover.px(10)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: row.device.label
            color: picker.popover.foreground
            font.family: picker.popover.monoFont
            font.pixelSize: picker.popover.px(13)
        }
        Rectangle {
            id: chip
            visible: typeof row.device.battery === "number"
            anchors.right: parent.right
            anchors.rightMargin: picker.popover.px(10)
            anchors.verticalCenter: parent.verticalCenter
            width: chipText.implicitWidth + picker.popover.px(14)
            height: chipText.implicitHeight + picker.popover.px(4)
            radius: height / 2
            color: Qt.rgba(picker.popover.foreground.r, picker.popover.foreground.g, picker.popover.foreground.b, 0.08)
            Text {
                id: chipText
                anchors.centerIn: parent
                text: chip.visible ? row.device.battery + " %" : ""
                color: picker.popover.dim
                font.family: picker.popover.monoFont
                font.pixelSize: picker.popover.px(11)
                font.features: ({ "tnum": 1 })
            }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.choose()
        }
    }

    Row {
        spacing: picker.popover.px(8)
        Rectangle {
            objectName: "pickerBack"
            width: picker.popover.px(26)
            height: width
            radius: picker.popover.px(8)
            color: Qt.rgba(picker.popover.foreground.r, picker.popover.foreground.g, picker.popover.foreground.b, back.containsMouse ? 0.12 : 0.06)
            Text {
                anchors.centerIn: parent
                text: "‹"
                color: picker.popover.foreground
                font.family: picker.popover.monoFont
                font.pixelSize: picker.popover.px(16)
            }
            MouseArea {
                id: back
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: picker.controller.closePicker()
            }
        }
        Text {
            objectName: "pickerTitle"
            anchors.verticalCenter: parent.verticalCenter
            text: picker.kind === "output" ? "Output" : "Input"
            color: picker.popover.foreground
            font.family: picker.popover.monoFont
            font.pixelSize: picker.popover.px(15)
            font.weight: Font.DemiBold
        }
    }

    Column {
        width: parent.width
        spacing: picker.popover.px(2)
        Repeater {
            objectName: "pickerRows"
            model: shownModel
            delegate: DeviceRow { devices: picker.shownByKey }
        }
        Text {
            objectName: "showHidden"
            visible: hiddenModel.count > 0 && !picker.revealed
            leftPadding: picker.popover.px(10)
            topPadding: picker.popover.px(4)
            bottomPadding: picker.popover.px(4)
            text: "Show %1 hidden".arg(hiddenModel.count)
            color: reveal.containsMouse ? picker.popover.foreground : picker.popover.dim
            font.family: picker.popover.monoFont
            font.pixelSize: picker.popover.px(12)
            MouseArea {
                id: reveal
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: picker.revealed = true
            }
        }
        Repeater {
            objectName: "hiddenRows"
            model: hiddenModel
            delegate: DeviceRow {
                devices: picker.hiddenByKey
                visible: picker.revealed
                opacity: 0.75
            }
        }
    }

    Item {
        width: parent.width
        height: footer.implicitHeight + picker.popover.px(10)
        Rectangle { width: parent.width; height: 1; color: picker.popover.hairline }
        Item {
            id: footer
            y: picker.popover.px(10)
            x: picker.popover.px(10)
            width: parent.width - picker.popover.px(20)
            implicitHeight: settings.implicitHeight
            Text {
                anchors.left: parent.left
                anchors.right: settings.left
                anchors.rightMargin: picker.popover.px(8)
                elide: Text.ElideRight
                text: "Ports, profiles, names"
                color: picker.popover.dim
                font.family: picker.popover.monoFont
                font.pixelSize: picker.popover.px(11.5)
            }
            Text {
                id: settings
                objectName: "pickerSettings"
                anchors.right: parent.right
                text: "Settings ›"
                color: settingsArea.containsMouse ? picker.popover.foreground : picker.popover.accent
                font.family: picker.popover.monoFont
                font.pixelSize: picker.popover.px(11.5)
                MouseArea {
                    id: settingsArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: picker.controller.openSettings()
                }
            }
        }
    }
}
