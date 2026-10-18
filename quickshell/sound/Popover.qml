pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "model.mjs" as Model

// The sound popover's card (docs/internals/sound-popover.md): header, the
// Devices and Apps tabs, the picker that slides over Devices, and the Apps
// status line. It draws plain JS objects from `controller` and calls it back:
//   properties  background, foreground, accent, accentInk, monoFont, uiScale,
//               ready, tab ("devices"|"apps"), picker (""|"output"|"input"),
//               output, input (DeviceView|null), outputs, inputs ({ shown, hidden }),
//               apps (AppView[]), targets (route targets), status, meter (0-1)
//   functions   setTab(t), openPicker(kind), closePicker(), choose(kind, key),
//               setVolume(key, value), setMuted(key, muted),
//               route(appKey, targetName | "default"), openSettings(),
//               openAdvanced(), close()
// The controller replaces its arrays on every change, so repeated rows are
// keyed (syncKeys) and updated in place, never rebuilt.
FocusScope {
    id: popover
    required property var controller

    // A bar popover keeps the bar's pixel sizes: uiScale is 1.
    function px(size) { return Math.round(size * controller.uiScale); }
    readonly property color background: controller.background
    readonly property color foreground: controller.foreground
    readonly property color accent: controller.accent
    readonly property color accentInk: controller.accentInk
    // Secondary text stays at 75 %: dimmer fails 4.5:1 on light palettes.
    readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.75)
    readonly property color hairline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
    readonly property string monoFont: controller.monoFont
    readonly property string iconFont: "Symbols Nerd Font"

    // Task 6 binds the mic's peak monitor to this: it runs only while seen.
    readonly property bool meterActive: controller.tab === "devices" && controller.picker === ""
    // The open menu (route or ⋯), if any; Escape is the menu's while it is set.
    property Popup openMenu: null

    readonly property var appsByKey: byKey(controller.apps)
    // What a row draws in the moment between its stream ending and its removal.
    readonly property var noApp: ({ key: "", serial: 0, name: "", icon: "", initials: "", volume: 0, muted: false,
        route: { label: "", pinned: false, target: "" }, tag: "", pending: false })
    readonly property var noDevice: ({ key: "", name: "", label: "", volume: 0, muted: false, battery: null,
        current: false, virtual: false })

    function byKey(items) {
        const map = {};
        for (let i = 0; items && i < items.length; i++) map[items[i].key] = items[i];
        return map;
    }
    // Make `model` (rows of { key }) match `items` in order, moving, inserting
    // and removing rows so the delegates of unchanged keys survive.
    function syncKeys(model, items) {
        const keys = (items || []).map(item => item.key);
        for (let i = model.count - 1; i >= 0; i--) if (keys.indexOf(model.get(i).key) < 0) model.remove(i);
        for (let i = 0; i < keys.length; i++) {
            let j = i;
            while (j < model.count && model.get(j).key !== keys[i]) j++;
            if (j === model.count) model.insert(i, { key: keys[i] });
            else if (j !== i) model.move(j, i, 1);
        }
    }
    // md-battery_outline, md-battery_10 … md-battery_90, md-battery
    function batteryGlyph(percent) {
        if (percent >= 95) return 0xf0079;
        if (percent < 10) return 0xf008e;
        return 0xf007a + Math.floor(percent / 10) - 1;
    }

    ListModel { id: appModel }
    Connections {
        target: popover.controller
        function onAppsChanged() { popover.syncKeys(appModel, popover.controller.apps); }
    }
    Component.onCompleted: syncKeys(appModel, controller.apps)

    // Escape backs out of the picker first. Off while a menu is open, so the
    // menu's own Escape closes only the menu.
    Shortcut {
        sequence: "Escape"
        enabled: popover.enabled && popover.openMenu === null
        onActivated: {
            if (popover.controller.picker !== "") popover.controller.closePicker();
            else popover.controller.close();
        }
    }

    width: px(340)
    height: frame.height

    // The update card's entrance: fade over 180 ms while scaling from 97 % and
    // dropping 8 px over 220 ms, from the clicked point of the bar; the leave
    // reverses it in 140 ms and then emits dismissed().
    property bool fromBottom: false
    property real originX: width / 2
    signal dismissed()
    property real fade: 0
    property real lift: 0
    opacity: fade
    transform: [
        Scale {
            origin.x: Math.max(0, Math.min(popover.width, popover.originX))
            origin.y: popover.fromBottom ? popover.height : 0
            xScale: 0.97 + 0.03 * popover.lift
            yScale: 0.97 + 0.03 * popover.lift
        },
        Translate { y: (popover.fromBottom ? 1 : -1) * popover.px(8) * (1 - popover.lift) }
    ]
    function appear() {
        leave.stop();
        enter.start();
        forceActiveFocus();
    }
    function disappear() {
        if (openMenu) openMenu.close();
        enter.stop();
        leave.start();
    }
    ParallelAnimation {
        id: enter
        NumberAnimation { target: popover; property: "fade"; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: popover; property: "lift"; to: 1; duration: 220; easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: leave
        NumberAnimation { target: popover; property: "fade"; to: 0; duration: 140; easing.type: Easing.InCubic }
        NumberAnimation { target: popover; property: "lift"; to: 0; duration: 140; easing.type: Easing.InCubic }
        onFinished: popover.dismissed()
    }

    component IconButton: Rectangle {
        id: button
        property int glyph
        property bool active: false
        signal clicked()
        width: popover.px(26)
        height: width
        radius: popover.px(8)
        color: Qt.rgba(popover.foreground.r, popover.foreground.g, popover.foreground.b,
            active || area.containsMouse ? 0.12 : 0.06)
        border.width: activeFocus ? 2 : 0
        border.color: popover.accent
        activeFocusOnTab: true
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        Keys.onSpacePressed: clicked()
        Text {
            anchors.centerIn: parent
            text: String.fromCodePoint(button.glyph)
            color: button.active || area.containsMouse ? popover.foreground : popover.dim
            font.family: popover.iconFont
            font.pixelSize: popover.px(13)
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }
    component Tab: Rectangle {
        id: tab
        required property string name
        required property string title
        readonly property bool checked: popover.controller.tab === name
        property int count: 0
        width: (tabBar.width - popover.px(6)) / 2
        height: popover.px(28)
        radius: popover.px(8)
        color: checked ? Qt.rgba(popover.foreground.r, popover.foreground.g, popover.foreground.b, 0.12) : "transparent"
        border.width: activeFocus ? 2 : 0
        border.color: popover.accent
        activeFocusOnTab: true
        Keys.onReturnPressed: popover.controller.setTab(name)
        Keys.onSpacePressed: popover.controller.setTab(name)
        Row {
            anchors.centerIn: parent
            spacing: popover.px(5)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tab.title
                color: tab.checked ? popover.foreground : popover.dim
                font.family: popover.monoFont
                font.pixelSize: popover.px(12)
            }
            Rectangle {
                objectName: tab.name + "Badge"
                readonly property string text: String(tab.count)
                visible: tab.count > 0
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(height, badgeText.implicitWidth + popover.px(8))
                height: popover.px(15)
                radius: height / 2
                color: popover.accent
                Text {
                    id: badgeText
                    anchors.centerIn: parent
                    text: parent.text
                    color: popover.accentInk
                    font.family: popover.monoFont
                    font.pixelSize: popover.px(10)
                    font.features: ({ "tnum": 1 })
                }
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: popover.controller.setTab(tab.name)
        }
    }

    Rectangle {
        id: frame
        width: parent.width
        // Mixed by the slide, so the card grows or shrinks as the picker moves.
        height: popover.px(28) + main.implicitHeight + (picker.implicitHeight - main.implicitHeight) * picker.shownFraction
        radius: popover.px(18)
        color: Qt.rgba(popover.background.r, popover.background.g, popover.background.b, 0.68)
        border.width: 1
        border.color: Qt.rgba(popover.foreground.r, popover.foreground.g, popover.foreground.b, 0.22)
        clip: true

        // Clicks inside the card never reach the close-on-outside-click area.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        Column {
            id: main
            x: popover.px(14) - frame.width * picker.shownFraction
            y: popover.px(14)
            width: frame.width - popover.px(28)
            spacing: popover.px(10)
            enabled: popover.controller.picker === ""
            visible: picker.shownFraction < 1

            Item {
                width: parent.width
                height: popover.px(26)
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    x: popover.px(2)
                    text: "Sound"
                    color: popover.foreground
                    font.family: popover.monoFont
                    font.pixelSize: popover.px(15)
                    font.weight: Font.DemiBold
                }
                Row {
                    anchors.right: parent.right
                    spacing: popover.px(4)
                    IconButton {
                        objectName: "settingsButton"
                        // md-cog
                        glyph: 0xf0493
                        onClicked: popover.controller.openSettings()
                    }
                    IconButton {
                        id: moreButton
                        objectName: "moreButton"
                        // md-dots_horizontal
                        glyph: 0xf01d8
                        active: moreMenu.visible
                        onClicked: moreMenu.visible ? moreMenu.close() : moreMenu.open()
                        Popup {
                            id: moreMenu
                            objectName: "moreMenu"
                            popupType: Popup.Item
                            x: moreButton.width - width
                            y: moreButton.height + popover.px(4)
                            width: popover.px(170)
                            padding: popover.px(4)
                            focus: true
                            onOpened: { popover.openMenu = moreMenu; advanced.forceActiveFocus(); }
                            onClosed: {
                                if (popover.openMenu === moreMenu) popover.openMenu = null;
                                moreButton.forceActiveFocus();
                            }
                            background: Rectangle {
                                radius: popover.px(10)
                                color: Qt.rgba(popover.background.r, popover.background.g, popover.background.b, 0.96)
                                border.width: 1
                                border.color: Qt.rgba(popover.foreground.r, popover.foreground.g, popover.foreground.b, 0.18)
                            }
                            contentItem: Rectangle {
                                id: advanced
                                objectName: "advancedEntry"
                                readonly property string text: "Advanced…"
                                implicitHeight: advancedText.implicitHeight + popover.px(10)
                                radius: popover.px(7)
                                color: advancedArea.containsMouse || activeFocus
                                    ? Qt.rgba(popover.foreground.r, popover.foreground.g, popover.foreground.b, 0.08) : "transparent"
                                function run() {
                                    moreMenu.close();
                                    popover.controller.openAdvanced();
                                }
                                Keys.onReturnPressed: run()
                                Keys.onEnterPressed: run()
                                Keys.onSpacePressed: run()
                                Text {
                                    id: advancedText
                                    x: popover.px(8)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: advanced.text
                                    color: popover.foreground
                                    font.family: popover.monoFont
                                    font.pixelSize: popover.px(12)
                                }
                                MouseArea {
                                    id: advancedArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: advanced.run()
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: tabBar
                objectName: "tabBar"
                width: parent.width
                height: popover.px(34)
                radius: popover.px(11)
                color: Qt.rgba(popover.foreground.r, popover.foreground.g, popover.foreground.b, 0.05)
                Row {
                    anchors.centerIn: parent
                    Tab { objectName: "tabDevices"; name: "devices"; title: "Devices" }
                    Tab { objectName: "tabApps"; name: "apps"; title: "Apps"; count: Model.badge(popover.controller.apps || []) }
                }
            }

            // One line for route failures; it outlives the row it was about.
            Text {
                objectName: "statusLine"
                visible: popover.controller.tab === "apps" && popover.controller.status !== ""
                width: parent.width
                leftPadding: popover.px(4)
                rightPadding: popover.px(4)
                elide: Text.ElideRight
                text: popover.controller.status
                color: popover.foreground
                font.family: popover.monoFont
                font.pixelSize: popover.px(12)
            }

            Item {
                id: body
                width: parent.width
                height: popover.controller.tab === "apps" ? apps.height : devices.implicitHeight
                Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                clip: true

                Column {
                    id: devices
                    width: parent.width
                    spacing: popover.px(8)
                    opacity: popover.controller.tab === "devices" ? 1 : 0
                    visible: opacity > 0
                    enabled: popover.controller.tab === "devices"
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                    DeviceCard { popover: popover; kind: "output"; width: parent.width }
                    DeviceCard { popover: popover; kind: "input"; width: parent.width }
                }

                Item {
                    id: apps
                    width: parent.width
                    // Room for about eight rows; more scroll, so the card stays under 560 px.
                    height: appModel.count ? Math.min(appColumn.implicitHeight, popover.px(400)) : empty.implicitHeight
                    opacity: popover.controller.tab === "apps" ? 1 : 0
                    visible: opacity > 0
                    enabled: popover.controller.tab === "apps"
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                    Text {
                        id: empty
                        objectName: "appsEmpty"
                        visible: appModel.count === 0
                        width: parent.width
                        topPadding: popover.px(24)
                        bottomPadding: popover.px(24)
                        horizontalAlignment: Text.AlignHCenter
                        text: popover.controller.ready ? "Nothing is playing" : "Sound server not running"
                        color: popover.dim
                        font.family: popover.monoFont
                        font.pixelSize: popover.px(12.5)
                    }
                    Flickable {
                        id: appsList
                        objectName: "appsList"
                        anchors.fill: parent
                        contentHeight: appColumn.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        Column {
                            id: appColumn
                            width: appsList.width
                            spacing: popover.px(4)
                            Repeater {
                                objectName: "appRows"
                                model: appModel
                                delegate: AppRow { popover: popover; width: appColumn.width }
                            }
                        }
                    }
                }
            }
        }

        Picker {
            id: picker
            popover: popover
            x: popover.px(14) + frame.width * (1 - shownFraction)
            y: popover.px(14)
            width: frame.width - popover.px(28)
            enabled: popover.controller.picker !== ""
            visible: shownFraction > 0
        }
    }
}
