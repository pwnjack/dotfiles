pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "pages.mjs" as Pages
import "about.mjs" as About

FocusScope {
    id: view
    required property var controller
    signal framePresented()
    property bool reportedFrame: false
    Connections {
        target: view.Window.window
        function onFrameSwapped() {
            if (!view.reportedFrame) { view.reportedFrame = true; view.framePresented(); }
        }
    }
    readonly property color background: controller.background
    readonly property color foreground: controller.foreground
    readonly property color accent: controller.accent
    readonly property color accentText: controller.accentText
    readonly property color plate: Qt.tint(background, Qt.rgba(foreground.r, foreground.g, foreground.b, 0.055))
    function tone(alpha) { return Qt.rgba(foreground.r, foreground.g, foreground.b, alpha); }
    // Surfaces are opaque tints of the background, so popups drawn with them hide what is under them.
    readonly property color raised: Qt.tint(background, tone(0.09))
    readonly property color hover: Qt.tint(background, tone(0.14))
    readonly property color pressed: Qt.tint(background, tone(0.2))
    readonly property color sidebar: Qt.tint(background, tone(0.025))
    readonly property color line: tone(0.08)
    // 75 %: secondary text stays above 4.5:1 on the plate for light palettes too.
    readonly property color dim: tone(0.75)
    // Errors tint the readable foreground towards red to keep alerts distinct from the accent.
    readonly property color warn: Qt.tint(foreground, Qt.rgba(0.88, 0.42, 0.42, 0.6))
    // Glyphs are Material Design icons from Symbols Nerd Font (ttf-nerd-fonts-symbols), kept as
    // hex code points: text, so they take the label's colour.
    readonly property string iconFont: "Symbols Nerd Font"
    function glyph(hex) { return hex ? String.fromCodePoint(parseInt(hex, 16)) : ""; }
    readonly property bool searching: !!controller.query.trim()
    readonly property var page: controller.catalog.categories.find(c => c.id === controller.category)
    // The page drawn by its own view, if any; a search shows rows only.
    readonly property string customPage: !searching && Pages.CUSTOM_PAGES.includes(controller.category) ? controller.category : ""
    readonly property var sections: Pages.pageSections(controller.catalog.categories, controller.visibleRows, searching)
    // Maintenance waits while a display change is pending: a reload would undo it.
    readonly property bool actionsIdle: !controller.pendingDisplay
    property alias actionsMenu: actionsMenu
    property double now: Date.now()
    property double autoRevertedFor: 0
    property bool justSaved: false
    // The visible countdown. systemd's guard reverts at 20 s even if this never fires.
    Timer {
        interval: 250; repeat: true
        running: !!view.controller.pendingDisplay
        onTriggered: {
            view.now = Date.now();
            const deadline = view.controller.pendingDisplay.deadline;
            // Once per deadline: a revert that failed must not retry every 250 ms.
            if (view.now >= deadline && !view.controller.busy && view.autoRevertedFor !== deadline) {
                view.autoRevertedFor = deadline;
                view.controller.revertDisplay();
            }
        }
    }
    Connections {
        target: view.controller
        // "Saved" for a moment after the queue drains without a problem.
        function onBusyChanged() {
            if (view.controller.busy) view.justSaved = false;
            else if (!view.controller.problem) { view.justSaved = true; savedTimer.restart(); }
        }
        function onCategoryChanged() { scroll.contentItem.contentY = 0; pageFade.restart(); }
    }
    Timer { id: savedTimer; interval: 1500; onTriggered: view.justSaved = false }
    function run(action) { actionsMenu.close(); controller.action(action); }
    focus: true
    Keys.onEscapePressed: controller.close()
    Shortcut { sequence: "Ctrl+F"; onActivated: search.forceActiveFocus() }
    // While the ⋯ menu is open, Escape closes the menu (its closePolicy), not the panel.
    Shortcut { sequence: "Escape"; enabled: !actionsMenu.visible; onActivated: view.controller.close() }
    Rectangle { anchors.fill: parent; color: Qt.rgba(view.background.r, view.background.g, view.background.b, 0.24) }
    MouseArea { anchors.fill: parent; onClicked: view.controller.close() }
    Rectangle {
        id: panel
        objectName: "settingsPanel"
        anchors.centerIn: parent
        width: Math.min(1080, parent.width - 48)
        height: Math.min(760, parent.height - 48)
        radius: 20
        color: view.background
        border.color: view.tone(0.14)
        MouseArea { anchors.fill: parent } // Keep clicks inside the panel from closing it.
        RowLayout {
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0
            Rectangle {
                Layout.preferredWidth: 236
                Layout.fillHeight: true
                color: view.sidebar
                radius: 19
                // Only the panel's outer corners are round: square off the sidebar's right side.
                Rectangle { anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: parent.right; width: parent.radius; color: parent.color }
                Rectangle { anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: parent.right; width: 1; color: view.line }
                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12; anchors.topMargin: 16; anchors.bottomMargin: 12
                    spacing: 12
                    TextField {
                        id: search
                        objectName: "settingsSearch"
                        Layout.fillWidth: true
                        Layout.leftMargin: 4; Layout.rightMargin: 4
                        implicitHeight: 32
                        leftPadding: 30; rightPadding: 10; topPadding: 0; bottomPadding: 0
                        verticalAlignment: TextInput.AlignVCenter
                        font.pixelSize: 13
                        placeholderText: "Search"
                        text: view.controller.query
                        onTextEdited: view.controller.query = text
                        color: view.foreground
                        placeholderTextColor: view.dim
                        selectionColor: view.accent
                        selectedTextColor: view.accentText
                        selectByMouse: true
                        Accessible.name: "Search settings"
                        background: Rectangle {
                            color: view.raised; radius: 8
                            border.width: search.activeFocus ? 2 : 0
                            border.color: view.accent
                            Text {
                                // md-magnify
                                x: 9; anchors.verticalCenter: parent.verticalCenter
                                text: view.glyph("f0349"); font.family: view.iconFont; font.pixelSize: 15
                                color: view.dim
                                Accessible.ignored: true
                            }
                            Text {
                                visible: !search.text && !search.activeFocus
                                anchors.right: parent.right; anchors.rightMargin: 9; anchors.verticalCenter: parent.verticalCenter
                                text: "Ctrl F"; font.pixelSize: 11; color: view.dim
                                Accessible.ignored: true
                            }
                        }
                    }
                    ListView {
                        id: categoryList
                        objectName: "categoryList"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        boundsBehavior: Flickable.StopAtBounds
                        // Only an overflowing list shows a bar, so hidden pages stay discoverable.
                        ScrollBar.vertical: ScrollBar { policy: categoryList.contentHeight > categoryList.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }
                        model: Pages.navEntries(view.controller.catalog.categories)
                        delegate: Item {
                            id: entry
                            required property var modelData
                            width: ListView.view.width
                            // A new group starts after a 10 px gap, as macOS separates its sidebar clusters.
                            height: nav.height + (modelData.gapBefore ? 10 : 0)
                            Button {
                                id: nav
                                objectName: "nav-" + entry.modelData.id
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 32
                                text: entry.modelData.title
                                hoverEnabled: true
                                readonly property bool selected: view.controller.category === entry.modelData.id && !view.searching
                                onClicked: view.controller.select(entry.modelData.id)
                                contentItem: RowLayout {
                                    spacing: 10
                                    Rectangle {
                                        Layout.leftMargin: 6
                                        implicitWidth: 22; implicitHeight: 22; radius: 6
                                        color: nav.selected ? Qt.rgba(view.accentText.r, view.accentText.g, view.accentText.b, 0.16)
                                            : Qt.rgba(view.accent.r, view.accent.g, view.accent.b, 0.22)
                                        Text {
                                            anchors.centerIn: parent
                                            text: view.glyph(entry.modelData.icon)
                                            font.family: view.iconFont; font.pixelSize: 14
                                            color: nav.selected ? view.accentText : view.accent
                                            Accessible.ignored: true
                                        }
                                    }
                                    Text {
                                        text: nav.text
                                        color: nav.selected ? view.accentText : view.foreground
                                        font.pixelSize: 13; font.weight: nav.selected ? Font.DemiBold : Font.Normal
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                                background: Rectangle {
                                    radius: 7
                                    color: nav.selected ? view.accent : nav.hovered ? view.tone(0.06) : "transparent"
                                    border.width: nav.activeFocus ? 2 : 0
                                    border.color: nav.selected ? view.accentText : view.accent
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        // Two quiet, centred lines above the card: a footnote, not content.
                        Label {
                            objectName: "accountSystemSummary"
                            readonly property var accountData: view.controller.about || ({})
                            visible: !!accountData.os || !!accountData.kernel
                            text: [accountData.os || "", accountData.kernel ? "Linux " + accountData.kernel.split("-")[0] : ""].filter(Boolean).join(" · ")
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            color: view.dim; font.pixelSize: 11; elide: Text.ElideRight
                        }
                        Label {
                            objectName: "accountSessionSummary"
                            readonly property var accountData: view.controller.about || ({})
                            readonly property string uptime: About.formatUptime(accountData.uptimeSeconds, true)
                            visible: !!accountData.hyprland || !!uptime
                            text: [accountData.hyprland ? "Hyprland " + accountData.hyprland : "", uptime ? "up " + uptime : ""].filter(Boolean).join(" · ")
                            Layout.fillWidth: true
                            Layout.topMargin: -6
                            horizontalAlignment: Text.AlignHCenter
                            color: view.dim; font.pixelSize: 11; elide: Text.ElideRight
                        }
                        AccountCard { Layout.fillWidth: true; controller: view.controller; theme: view }
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0
                Item {
                    id: titleBar
                    Layout.fillWidth: true
                    implicitHeight: 52
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 28; anchors.rightMargin: 14
                        spacing: 8
                        Label {
                            objectName: "pageTitle"
                            text: view.searching ? "Search results" : (view.page?.title || "Settings")
                            color: view.foreground; font.pixelSize: 16; font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        // Transient status beside the buttons. It keeps its last text while fading
                        // out, so nothing shifts as a save or read starts or ends.
                        Label {
                            objectName: "panelStatus"
                            // "Saved" outranks the read every write triggers, or that read would hide it.
                            readonly property string current: view.controller.busy ? "Saving…" : view.justSaved ? "Saved" : view.controller.loading ? "Reading settings…" : ""
                            property string shown: ""
                            onCurrentChanged: if (current) shown = current
                            Component.onCompleted: shown = current
                            text: shown
                            opacity: current ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            color: view.dim; font.pixelSize: 12
                            Layout.rightMargin: 6
                        }
                        IconButton {
                            id: moreButton
                            objectName: "moreActions"
                            theme: view
                            // md-dots_horizontal
                            glyph: view.glyph("f01d8")
                            label: "More actions"
                            active: actionsMenu.visible
                            // Read before opening: the popup takes focus, and with it the button's visualFocus.
                            onClicked: { actionsMenu.byKeyboard = visualFocus; actionsMenu.visible ? actionsMenu.close() : actionsMenu.open(); }
                        }
                        IconButton {
                            objectName: "closeSettings"
                            theme: view
                            // md-close
                            glyph: view.glyph("f0156")
                            label: "Close"
                            onClicked: view.controller.close()
                        }
                    }
                    Popup {
                        id: actionsMenu
                        objectName: "actionsMenu"
                        popupType: Popup.Item
                        x: titleBar.width - width - 14
                        y: titleBar.height - 8
                        width: 240
                        padding: 5
                        property bool byKeyboard: false
                        // Keyboard users land on the first entry and return to ⋯ afterwards.
                        focus: true
                        // The first entry that can run: Reload waits while a save is in flight.
                        // Focus always lands inside so arrows work, but only a keyboard opening (⋯ reached
                        // with Tab) shows it: a mouse opening highlights nothing until hover.
                        onOpened: ([reloadEntry, restartEntry, updateEntry].find(entry => entry.enabled) || actionsMenu.contentItem)
                            .forceActiveFocus(actionsMenu.byKeyboard ? Qt.TabFocusReason : Qt.OtherFocusReason)
                        // Hand focus back the way the menu came, so a keyboard user can reopen it
                        // (Space) and still get the highlight.
                        onClosed: moreButton.forceActiveFocus(actionsMenu.byKeyboard ? Qt.TabFocusReason : Qt.OtherFocusReason)
                        background: Rectangle { radius: 10; color: view.plate; border.color: view.tone(0.18) }
                        contentItem: ColumnLayout {
                            spacing: 2
                            MenuEntry { id: reloadEntry; objectName: "reloadHyprland"; theme: view; glyph: "f0450"; KeyNavigation.down: restartEntry; text: "Reload Hyprland"; enabled: !view.controller.busy && view.actionsIdle; onClicked: view.run("reload") }
                            MenuEntry { id: restartEntry; objectName: "restartWaybar"; theme: view; glyph: view.controller.catalog.categories.find(c => c.id === "bar")?.icon || ""; KeyNavigation.up: reloadEntry; KeyNavigation.down: updateEntry; text: "Restart bar"; enabled: view.actionsIdle; onClicked: view.run("waybar") }
                            Rectangle { Layout.fillWidth: true; Layout.leftMargin: 6; Layout.rightMargin: 6; implicitHeight: 1; color: view.line }
                            MenuEntry {
                                id: updateEntry
                                KeyNavigation.up: restartEntry
                                objectName: "updateSystem"; theme: view; text: "Update system…"
                                // md-package_up
                                glyph: "f03d5"
                                hint: view.controller.values["apps.aurhelper"]?.value || ""
                                enabled: view.actionsIdle
                                onClicked: view.run("update")
                            }
                        }
                    }
                }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: view.line }
                ColumnLayout {
                    visible: !!view.controller.problem || !!view.controller.authPending || !!view.controller.pendingDisplay
                    Layout.fillWidth: true
                    Layout.leftMargin: 28; Layout.rightMargin: 28; Layout.topMargin: 16
                    spacing: 8
                    Rectangle {
                        visible: !!view.controller.problem
                        Layout.fillWidth: true
                        implicitHeight: problemRow.implicitHeight + 20
                        radius: 10; color: view.plate; border.color: view.warn
                        RowLayout {
                            id: problemRow
                            anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 14; anchors.rightMargin: 14
                            spacing: 8
                            Text { text: view.glyph("f002a"); font.family: view.iconFont; font.pixelSize: 15; color: view.warn; Accessible.ignored: true }
                            Label { text: view.controller.problem; color: view.foreground; wrapMode: Text.Wrap; Layout.fillWidth: true; font.pixelSize: 13; Accessible.role: Accessible.AlertMessage }
                        }
                    }
                    Rectangle {
                        objectName: "authPending"
                        visible: !!view.controller.authPending
                        Layout.fillWidth: true
                        implicitHeight: authLabel.implicitHeight + 20
                        radius: 10
                        color: Qt.rgba(view.accent.r, view.accent.g, view.accent.b, 0.14)
                        border.color: Qt.rgba(view.accent.r, view.accent.g, view.accent.b, 0.4)
                        Label { id: authLabel; anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.margins: 14; text: "Waiting for authentication…"; color: view.foreground; font.pixelSize: 13; wrapMode: Text.WordWrap; Accessible.role: Accessible.AlertMessage }
                    }
                    Rectangle {
                        id: pendingBanner
                        objectName: "displayPending"
                        visible: !!view.controller.pendingDisplay
                        readonly property int secondsLeft: view.controller.pendingDisplay ? Math.max(0, Math.ceil((view.controller.pendingDisplay.deadline - view.now) / 1000)) : 0
                        Layout.fillWidth: true
                        implicitHeight: pendingRow.implicitHeight + 20
                        radius: 10
                        color: Qt.rgba(view.accent.r, view.accent.g, view.accent.b, 0.14)
                        border.color: Qt.rgba(view.accent.r, view.accent.g, view.accent.b, 0.4)
                        RowLayout {
                            id: pendingRow
                            anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 14; anchors.rightMargin: 10
                            spacing: 8
                            Label { objectName: "displayCountdown"; text: "Keep this display layout? Reverting in " + pendingBanner.secondsLeft + " s"; color: view.foreground; font.pixelSize: 13; Layout.fillWidth: true; wrapMode: Text.WordWrap; Accessible.role: Accessible.AlertMessage }
                            PanelButton { objectName: "revertDisplay"; theme: view; text: "Revert"; enabled: !view.controller.busy; onClicked: view.controller.revertDisplay() }
                            PanelButton { objectName: "keepDisplay"; theme: view; primary: true; text: "Keep"; enabled: !view.controller.busy; onClicked: view.controller.keepDisplay() }
                        }
                    }
                }
                ScrollView {
                    id: scroll
                    objectName: "settingsScroll"
                    opacity: view.controller.loaded ? 1 : 0
                    enabled: view.controller.loaded
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: availableWidth
                    contentHeight: content.implicitHeight + 40
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ColumnLayout {
                        id: content
                        x: 28; y: 20
                        width: scroll.availableWidth - 56
                        spacing: 22
                        NumberAnimation { id: pageFade; target: content; property: "opacity"; from: 0; to: 1; duration: 150 }
                        Repeater {
                            model: view.customPage === "monitors" ? view.controller.monitors : []
                            delegate: DisplayCard {
                                required property var modelData
                                Layout.fillWidth: true
                                monitor: modelData
                                theme: view
                                controller: view.controller
                            }
                        }
                        NetworkView {
                            visible: view.customPage === "network"
                            Layout.fillWidth: true
                            controller: view.controller
                            theme: view
                        }
                        StartupView {
                            visible: view.customPage === "startup"
                            Layout.fillWidth: true
                            controller: view.controller
                            theme: view
                        }
                        AboutView {
                            visible: view.customPage === "about"
                            Layout.fillWidth: true
                            controller: view.controller
                            theme: view
                        }
                        DevicesView {
                            visible: view.customPage === "devices"
                            Layout.fillWidth: true
                            controller: view.controller
                            theme: view
                        }
                        CalendarView {
                            visible: view.customPage === "calendar"
                            Layout.fillWidth: true
                            controller: view.controller
                            theme: view
                        }
                        Label {
                            objectName: "noSettingsMatch"
                            // Never under a custom view: its rows are legitimately empty of generic controls.
                            visible: !view.controller.loading && !view.controller.visibleRows.length && (view.searching || !view.customPage)
                            text: "No settings match your search."
                            color: view.dim; font.pixelSize: 13
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 40
                        }
                        Repeater {
                            model: view.sections
                            delegate: SettingsSection {
                                id: group
                                required property var modelData
                                objectName: "section-" + modelData.key
                                theme: view
                                title: modelData.title
                                footer: modelData.footer
                                actions: modelData.actions
                                actionsEnabled: view.actionsIdle
                                onTriggered: action => view.controller.action(action)
                                Repeater {
                                    model: group.modelData.rows
                                    delegate: SettingControl {
                                        required property var modelData
                                        required property int index
                                        divider: index > 0
                                        row: modelData
                                        theme: view
                                        settingState: view.controller.values[modelData.id] || ({})
                                        controller: view.controller
                                    }
                                }
                            }
                        }
                        // Displays: the per-machine rules file and the automatic main display, last.
                        SettingsSection {
                            visible: view.customPage === "monitors"
                            theme: view
                            title: "Display rules"
                            PanelRow {
                                theme: view
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 2
                                    Label { text: "monitors.lua"; color: view.foreground; font.pixelSize: 13; font.weight: Font.Medium; Layout.fillWidth: true }
                                    Label { text: "Per-machine rules written by this page, kept outside the repo"; color: view.dim; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                }
                                PanelButton { objectName: "editDisplaysFile"; theme: view; text: "Edit file"; enabled: !view.controller.pendingDisplay; onClicked: view.controller.action("displays-file") }
                            }
                            PanelRow {
                                theme: view
                                divider: true
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 2
                                    Label { text: "Main display"; color: view.foreground; font.pixelSize: 13; font.weight: Font.Medium; Layout.fillWidth: true }
                                    Label { text: view.controller.mainMonitor ? "Set to " + view.controller.mainMonitor : "Automatic: the first display Hyprland reports"; color: view.dim; font.pixelSize: 12 }
                                }
                                PanelButton { objectName: "automaticMainDisplay"; theme: view; text: "Use automatic"; enabled: !!view.controller.mainMonitor && !view.controller.busy && !view.controller.pendingDisplay; onClicked: view.controller.submit({op: "mainMonitor", value: ""}) }
                            }
                        }
                    }
                }
            }
        }
    }
    // A row of the ⋯ menu. Inline components cannot see this file's ids, so it takes the theme.
    component MenuEntry: Button {
        id: menuEntry
        required property var theme
        property string hint: ""
        // A Nerd Font code point, as the catalog stores page icons.
        property string glyph: ""
        Layout.fillWidth: true
        implicitHeight: 30
        leftPadding: 10; rightPadding: 10
        hoverEnabled: true
        opacity: enabled ? 1 : 0.42
        readonly property bool lit: hovered || visualFocus
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        contentItem: RowLayout {
            spacing: 10
            Text {
                objectName: menuEntry.objectName + "-icon"
                visible: !!menuEntry.glyph
                text: menuEntry.glyph ? String.fromCodePoint(parseInt(menuEntry.glyph, 16)) : ""
                font.family: menuEntry.theme.iconFont; font.pixelSize: 15
                color: menuEntry.lit ? menuEntry.theme.accentText : menuEntry.theme.accent
                horizontalAlignment: Text.AlignHCenter
                Layout.preferredWidth: 18
                Accessible.ignored: true
            }
            Text { text: menuEntry.text; color: menuEntry.lit ? menuEntry.theme.accentText : menuEntry.theme.foreground; font.pixelSize: 13; Layout.fillWidth: true }
            Text { visible: !!menuEntry.hint; text: menuEntry.hint; color: menuEntry.lit ? menuEntry.theme.accentText : menuEntry.theme.dim; font.pixelSize: 11; elide: Text.ElideLeft; Layout.maximumWidth: 110 }
        }
        background: Rectangle { radius: 6; color: menuEntry.lit ? menuEntry.theme.accent : "transparent" }
    }
}
