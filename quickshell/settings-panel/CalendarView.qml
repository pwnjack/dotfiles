pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The iCloud account and which calendars show. shell.qml re-reads calendarStatus
// every 5 s while this page is on screen. The "New events" rows below come from
// catalog.json like any other section.
ColumnLayout {
    id: page
    required property var controller
    required property var theme
    objectName: "calendarView"
    readonly property var model: controller.calendar
    readonly property bool signedIn: !!model && !!model.account
    spacing: 22
    SettingsSection {
        theme: page.theme
        title: "Account"
        footer: page.signedIn ? "Events sync every 15 minutes, and whenever the calendar card opens."
                              : "Use an app-specific password, not your Apple ID password."
        PanelRow {
            objectName: "signInRow"
            visible: !page.signedIn
            theme: page.theme
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
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
                        text: "Create an app-specific password"
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
        PanelRow {
            objectName: "signedInRow"
            visible: page.signedIn
            theme: page.theme
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label { objectName: "calendarAccount"; text: page.model ? page.model.account : ""; color: page.theme.foreground; font.pixelSize: 14 }
                Label {
                    objectName: "syncLine"
                    text: page.model ? page.model.line : ""
                    color: page.model && page.model.status && page.model.status.state === "failed" ? page.theme.warn : page.theme.dim
                    font.pixelSize: 13
                }
            }
            PanelButton {
                objectName: "syncNow"
                theme: page.theme
                text: "Sync now"
                onClicked: page.controller.calendarRequest({ op: "calendarSync" })
            }
            PanelButton {
                objectName: "signOut"
                theme: page.theme
                property bool confirm: false
                text: confirm ? "Confirm sign out" : "Sign out"
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
        footer: "Hidden calendars stay on your iPhone; they leave the bar and the calendar card."
        PanelRow {
            visible: !(page.model && page.model.calendars && page.model.calendars.length)
            theme: page.theme
            Label { text: "Calendars appear after the first sync."; color: page.theme.dim; font.pixelSize: 13 }
        }
        Repeater {
            model: page.signedIn && page.model ? page.model.calendars : []
            delegate: PanelRow {
                required property var modelData
                theme: page.theme
                Rectangle { width: 10; height: 10; radius: 5; color: modelData.color || page.theme.accent }
                Label {
                    text: modelData.name + (modelData.writable ? "" : "  (read-only)")
                    color: page.theme.foreground
                    font.pixelSize: 14
                    Layout.fillWidth: true
                }
                PanelSwitch {
                    objectName: "show-" + modelData.name
                    theme: page.theme
                    checked: modelData.shown
                    onToggled: page.controller.calendarRequest({ op: "calendarShow", name: modelData.name, shown: checked })
                }
            }
        }
    }
}
