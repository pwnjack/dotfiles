pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

// One playing stream on Apps: icon (or two initials), name, the route label
// that opens the route menu, volume and mute. The row is keyed by stream: the
// popover updates it in place, so a drag or an open menu survives PipeWire
// changes, and the menu closes itself when the stream ends.
Item {
    id: row
    required property var popover
    required property string key
    readonly property var controller: popover.controller
    readonly property bool gone: !popover.appsByKey[key]
    readonly property var app: popover.appsByKey[key] || popover.noApp
    implicitHeight: popover.px(50)
    onGoneChanged: if (gone) menu.close()

    // Default, the shown real outputs, a hidden device the stream is pinned
    // to, then the virtual sinks. Default is checked only when unpinned, and
    // nothing is checked while the pins cannot be read (pinsKnown).
    readonly property var entries: {
        const targets = controller.targets || [];
        const route = app.route;
        const known = controller.pinsKnown;
        const list = [{ key: "default", label: "Default (follows Devices)", checked: known && route.target === "" }];
        const entry = target => ({ key: target.name, label: target.label, checked: known && target.name === route.target });
        const real = targets.filter(target => !target.virtual);
        const virtual = targets.filter(target => target.virtual);
        for (let i = 0; i < real.length; i++) list.push(entry(real[i]));
        if (route.target && !targets.some(target => target.name === route.target))
            list.push({ key: route.target, label: route.label, checked: known });
        for (let i = 0; i < virtual.length; i++) list.push(entry(virtual[i]));
        return list;
    }
    readonly property var entryByKey: popover.byKey(entries)
    // Keyed like the rows, so a PipeWire change keeps the menu's focus and hover.
    ListModel { id: menuModel }
    onEntriesChanged: popover.syncKeys(menuModel, entries)
    Component.onCompleted: popover.syncKeys(menuModel, entries)
    function choose(entry) {
        menu.close();
        if (!entry.checked) controller.route(app.key, entry.key);
    }

    Rectangle {
        id: avatar
        width: row.popover.px(22)
        height: width
        y: row.popover.px(4)
        radius: row.popover.px(6)
        color: Qt.rgba(row.popover.foreground.r, row.popover.foreground.g, row.popover.foreground.b, 0.1)
        Image {
            id: icon
            anchors.fill: parent
            anchors.margins: row.popover.px(2)
            visible: status === Image.Ready
            source: row.app.icon ? "image://icon/" + row.app.icon : ""
            sourceSize.width: width
            sourceSize.height: height
            asynchronous: true
        }
        Text {
            anchors.centerIn: parent
            visible: !icon.visible
            text: row.app.initials
            color: row.popover.dim
            font.family: row.popover.monoFont
            font.pixelSize: row.popover.px(10.5)
        }
    }

    Text {
        id: name
        objectName: "appName"
        anchors.left: avatar.right
        anchors.leftMargin: row.popover.px(8)
        y: row.popover.px(2)
        width: Math.min(implicitWidth, routeLabel.x - x - row.popover.px(8))
        elide: Text.ElideRight
        text: row.app.name
        color: row.popover.foreground
        font.family: row.popover.monoFont
        font.pixelSize: row.popover.px(12.5)
    }

    Rectangle {
        id: routeLabel
        objectName: "routeLabel"
        anchors.right: parent.right
        anchors.verticalCenter: name.verticalCenter
        width: routeRow.implicitWidth + row.popover.px(10)
        height: routeRow.implicitHeight + row.popover.px(4)
        radius: row.popover.px(6)
        color: routeArea.containsMouse || menu.visible
            ? Qt.rgba(row.popover.foreground.r, row.popover.foreground.g, row.popover.foreground.b, 0.08) : "transparent"
        border.width: activeFocus ? 2 : 0
        border.color: row.popover.accent
        activeFocusOnTab: true
        Keys.onReturnPressed: menu.open()
        Keys.onEnterPressed: menu.open()
        Keys.onSpacePressed: menu.open()
        Row {
            id: routeRow
            anchors.centerIn: parent
            spacing: row.popover.px(4)
            Rectangle {
                visible: row.app.tag !== ""
                anchors.verticalCenter: parent.verticalCenter
                width: tagText.implicitWidth + row.popover.px(8)
                height: tagText.implicitHeight
                radius: row.popover.px(5)
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(row.popover.accent.r, row.popover.accent.g, row.popover.accent.b, 0.5)
                Text {
                    id: tagText
                    anchors.centerIn: parent
                    text: row.app.tag
                    color: row.popover.accent
                    font.family: row.popover.monoFont
                    font.pixelSize: row.popover.px(10)
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                // At most about half the row, so the name keeps the rest.
                width: Math.min(implicitWidth, row.popover.px(130))
                elide: Text.ElideRight
                text: row.app.route.label
                // A requested route shows until the stream follows it.
                font.italic: row.app.pending
                color: menu.visible ? row.popover.accent : row.popover.dim
                font.family: row.popover.monoFont
                font.pixelSize: row.popover.px(11)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                // md-chevron_down
                text: String.fromCodePoint(0xf0140)
                color: row.popover.dim
                font.family: row.popover.iconFont
                font.pixelSize: row.popover.px(11)
            }
        }
        MouseArea {
            id: routeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: menu.visible ? menu.close() : menu.open()
        }
    }

    Text {
        id: mute
        objectName: "appMute"
        anchors.left: name.left
        anchors.verticalCenter: slider.verticalCenter
        width: row.popover.px(18)
        // md-volume_high / md-volume_off
        text: String.fromCodePoint(row.app.muted ? 0xf0581 : 0xf057e)
        color: muteArea.containsMouse ? row.popover.foreground : row.popover.dim
        font.family: row.popover.iconFont
        font.pixelSize: row.popover.px(13)
        MouseArea {
            id: muteArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.controller.setMuted(row.app.key, !row.app.muted)
        }
    }
    VolumeSlider {
        id: slider
        objectName: "appSlider"
        popover: row.popover
        anchors.left: mute.right
        anchors.leftMargin: row.popover.px(4)
        anchors.right: parent.right
        y: name.y + name.height + row.popover.px(4)
        key: row.app.key
        value: row.app.volume
        muted: row.app.muted
        onCommit: (key, v) => row.controller.setVolume(key, v)
    }

    Popup {
        id: menu
        objectName: "routeMenu"
        // Keep the menu in the popover's scene, independent of platform menus.
        popupType: Popup.Item
        parent: routeLabel
        x: routeLabel.width - width
        y: routeLabel.height + row.popover.px(4)
        width: row.popover.px(230)
        margins: row.popover.px(8)
        padding: row.popover.px(4)
        focus: true
        // The popover's Escape shortcut is off while a menu is open (openMenu),
        // so Escape closes only the menu.
        onOpened: {
            row.popover.openMenu = menu;
            const entries = menuEntries;
            let first = entries.itemAt(0);
            for (let i = 0; i < entries.count; i++) if (entries.itemAt(i).checked) first = entries.itemAt(i);
            if (first) first.forceActiveFocus();
        }
        onClosed: {
            if (row.popover.openMenu === menu) row.popover.openMenu = null;
            if (row.gone) row.popover.forceActiveFocus();
            else routeLabel.forceActiveFocus();
        }
        Component.onDestruction: if (row.popover.openMenu === menu) row.popover.openMenu = null
        background: Rectangle {
            radius: row.popover.px(10)
            color: Qt.rgba(row.popover.background.r, row.popover.background.g, row.popover.background.b, 0.96)
            border.width: 1
            border.color: Qt.rgba(row.popover.foreground.r, row.popover.foreground.g, row.popover.foreground.b, 0.18)
        }
        contentItem: Column {
            spacing: row.popover.px(2)
            Repeater {
                id: menuEntries
                objectName: "menuEntries"
                model: menuModel
                delegate: Rectangle {
                    id: entry
                    required property string key
                    required property int index
                    readonly property var choice: row.entryByKey[key] || ({ key: key, label: "", checked: false })
                    readonly property string text: choice.label
                    readonly property bool checked: choice.checked
                    width: menu.availableWidth
                    height: entryText.implicitHeight + row.popover.px(10)
                    radius: row.popover.px(7)
                    color: checked ? Qt.rgba(row.popover.accent.r, row.popover.accent.g, row.popover.accent.b, 0.22)
                         : entryArea.containsMouse || activeFocus
                            ? Qt.rgba(row.popover.foreground.r, row.popover.foreground.g, row.popover.foreground.b, 0.08)
                            : "transparent"
                    border.width: activeFocus ? 1 : 0
                    border.color: row.popover.accent
                    Keys.onReturnPressed: row.choose(choice)
                    Keys.onEnterPressed: row.choose(choice)
                    Keys.onSpacePressed: row.choose(choice)
                    Keys.onDownPressed: { const next = menuEntries.itemAt(index + 1); if (next) next.forceActiveFocus(); }
                    Keys.onUpPressed: { const prev = menuEntries.itemAt(index - 1); if (prev) prev.forceActiveFocus(); }
                    Text {
                        id: entryText
                        x: row.popover.px(8)
                        width: parent.width - row.popover.px(16)
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: entry.text
                        color: row.popover.foreground
                        font.family: row.popover.monoFont
                        font.pixelSize: row.popover.px(12)
                    }
                    MouseArea {
                        id: entryArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: row.choose(entry.choice)
                    }
                }
            }
        }
    }
}
