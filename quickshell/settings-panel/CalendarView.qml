pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The calendar account and which calendars show. shell.qml re-reads calendarStatus
// every 5 s while this page is on screen. The "Events" and "New events" rows below
// come from catalog.json like any other section.
ColumnLayout {
    id: page
    required property var controller
    required property var theme
    objectName: "calendarView"
    readonly property var model: controller.calendar
    readonly property bool signedIn: !!model && !!model.account
    // The account type, named wherever the account is: only iCloud is supported today.
    readonly property string provider: "iCloud"
    readonly property string providerGlyph: String.fromCodePoint(0xF0038)     // md-apple_icloud
    readonly property bool failed: !!model && !!model.status && model.status.state === "failed"
    // Sync now shows it is working until status.json records an attempt newer than the one
    // shown when it was pressed (sync.sh may wait up to 120 s for its lock; past that the
    // button is offered again). -1: no sync asked for.
    property double syncBaseline: -1
    readonly property double lastAttempt: model && model.status ? (model.status.lastAttempt || 0) : 0
    readonly property bool syncing: syncBaseline >= 0 && lastAttempt <= syncBaseline
    onSyncingChanged: if (!syncing) syncBaseline = -1
    Timer { interval: 130000; running: page.syncing; onTriggered: page.syncBaseline = -1 }
    spacing: 22

    // The account's badge: the provider's mark on an accent tile, as the Devices page draws its devices.
    component Badge: Rectangle {
        implicitWidth: 36; implicitHeight: 36; radius: 9
        color: Qt.rgba(page.theme.accent.r, page.theme.accent.g, page.theme.accent.b, 0.22)
        Text {
            anchors.centerIn: parent
            text: page.providerGlyph
            font.family: page.theme.iconFont; font.pixelSize: 21
            color: page.theme.accent
            Accessible.ignored: true
        }
    }

    SettingsSection {
        theme: page.theme
        title: "Account"
        footer: page.signedIn ? "" : "Apple requires an app-specific password for calendar apps; your Apple ID password will not work."
        // Signed out: what is being set up, then the two fields.
        PanelRow {
            objectName: "signInRow"
            visible: !page.signedIn
            theme: page.theme
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                RowLayout {
                    spacing: 12
                    Badge {}
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label { objectName: "signInProvider"; text: page.provider; color: page.theme.foreground; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Label { text: "Sign in to show its calendars on the bar and in the calendar card"; color: page.theme.dim; font.pixelSize: 12
                            wrapMode: Text.Wrap; Layout.fillWidth: true }
                    }
                }
                PanelField { id: appleId; objectName: "appleIdField"; theme: page.theme; placeholderText: "Apple ID"; Layout.fillWidth: true }
                PanelField {
                    id: password
                    objectName: "passwordField"
                    theme: page.theme
                    placeholderText: "App-specific password"
                    echoMode: TextInput.Password
                    Layout.fillWidth: true
                }
                RowLayout {
                    Label {
                        objectName: "appPasswordLink"
                        text: "Create an app-specific password ↗"
                        color: page.theme.accent
                        font.pixelSize: 13
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Qt.openUrlExternally("https://account.apple.com")
                        }
                    }
                    Item { Layout.fillWidth: true }
                    PanelButton {
                        objectName: "signIn"
                        theme: page.theme
                        primary: true
                        text: "Sign in"
                        enabled: appleId.text.trim() !== "" && password.text !== ""
                        onClicked: {
                            page.controller.calendarRequest({ op: "calendarSignIn", appleId: appleId.text, password: password.text });
                            password.text = "";
                        }
                    }
                }
            }
        }
        // Signed in: who, then how the sync is doing, then the way out. Each row has one job.
        PanelRow {
            objectName: "signedInRow"
            visible: page.signedIn
            theme: page.theme
            Badge {}
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label { objectName: "providerName"; text: page.provider; color: page.theme.foreground; font.pixelSize: 14; font.weight: Font.DemiBold }
                Label { objectName: "calendarAccount"; text: page.model ? page.model.account : ""; color: page.theme.dim; font.pixelSize: 12
                    elide: Text.ElideRight; Layout.fillWidth: true }
            }
        }
        PanelRow {
            objectName: "syncRow"
            visible: page.signedIn
            theme: page.theme
            divider: true
            Rectangle {
                objectName: "syncDot"
                implicitWidth: 8; implicitHeight: 8; radius: 4
                color: page.failed ? page.theme.warn : page.theme.accent
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label {
                    objectName: "syncLine"
                    text: page.model ? page.model.line : ""
                    color: page.failed ? page.theme.warn : page.theme.foreground
                    font.pixelSize: 13
                    wrapMode: Text.Wrap; Layout.fillWidth: true
                }
                Label { text: "Every 15 minutes, and whenever the calendar card opens"; color: page.theme.dim; font.pixelSize: 12
                    wrapMode: Text.Wrap; Layout.fillWidth: true }
            }
            PanelButton {
                objectName: "syncNow"
                theme: page.theme
                text: page.syncing ? "Syncing…" : "Sync now"
                enabled: !page.syncing
                onClicked: {
                    page.syncBaseline = page.lastAttempt;
                    page.controller.calendarRequest({ op: "calendarSync" });
                }
            }
        }
        PanelRow {
            objectName: "signOutRow"
            visible: page.signedIn
            theme: page.theme
            divider: true
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label { text: "Sign out"; color: page.theme.foreground; font.pixelSize: 13 }
                Label {
                    objectName: "signOutNote"
                    text: signOut.confirm ? "Press again to sign out. Your events stay in " + page.provider + "."
                                          : "Removes the account and this computer's copy of its calendars"
                    color: signOut.confirm ? page.theme.warn : page.theme.dim
                    font.pixelSize: 12
                    wrapMode: Text.Wrap; Layout.fillWidth: true
                }
            }
            PanelButton {
                id: signOut
                objectName: "signOut"
                theme: page.theme
                danger: true
                property bool confirm: false
                primary: confirm
                text: confirm ? "Confirm sign out" : "Sign out"
                // An unanswered confirmation lapses, so a later stray click cannot sign out.
                Timer { interval: 5000; running: signOut.confirm; onTriggered: signOut.confirm = false }
                onClicked: {
                    if (!confirm) { confirm = true; return; }
                    confirm = false;
                    page.controller.calendarRequest({ op: "calendarSignOut" });
                }
            }
        }
    }
    SettingsSection {
        visible: page.signedIn
        theme: page.theme
        title: "Calendars"
        footer: "Hidden calendars are left out of the bar and the calendar card. Nothing is removed from " + page.provider + "."
        PanelRow {
            visible: !(page.model && page.model.calendars && page.model.calendars.length)
            theme: page.theme
            Label { text: "Calendars appear after the first sync."; color: page.theme.dim; font.pixelSize: 13 }
        }
        Repeater {
            model: page.signedIn && page.model ? page.model.calendars : []
            delegate: PanelRow {
                id: calRow
                required property var modelData
                required property int index
                theme: page.theme
                divider: index > 0
                Rectangle { implicitWidth: 10; implicitHeight: 10; radius: 5; color: calRow.modelData.color || page.theme.accent }
                Label {
                    text: calRow.modelData.name
                    color: page.theme.foreground
                    font.pixelSize: 14
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Label {
                    visible: !calRow.modelData.writable
                    text: "Read-only"
                    color: page.theme.dim
                    font.pixelSize: 12
                }
                PanelSwitch {
                    objectName: "show-" + calRow.modelData.name
                    theme: page.theme
                    checked: calRow.modelData.shown
                    onToggled: page.controller.calendarRequest({ op: "calendarShow", name: calRow.modelData.name, shown: checked })
                }
            }
        }
    }
}
