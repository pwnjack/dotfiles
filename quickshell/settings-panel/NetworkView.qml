pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Wi-Fi, wired and VPN in one view. Every write goes through controller.submit,
// so the queue, the stdin path and the post-write refresh are the ones every row uses.
ColumnLayout {
    id: page
    required property var controller
    required property var theme
    readonly property var model: controller.network
    readonly property var radio: controller.values["network.wifi"] || ({})
    property string expanded: ""
    // Kept off the delegates: a live read replaces controller.network with fresh
    // arrays on every poll, which recreates delegates and would otherwise wipe
    // whatever the user had half-typed into the password field.
    property string pskText: ""
    property bool pskFocused: false
    spacing: 22
    // Nerd Font glyphs by code point: pasted private-use characters vanish. Index = bars (1-4).
    readonly property var bars: ["", String.fromCodePoint(0xF091F), String.fromCodePoint(0xF0922), String.fromCodePoint(0xF0925), String.fromCodePoint(0xF0928)]
    readonly property string lock: String.fromCodePoint(0xF033E)
    function validPsk(text) { return /^[\x20-\x7e]{8,63}$/.test(text) || /^[0-9a-fA-F]{64}$/.test(text) }
    // UTF-8 length without TextEncoder (absent in QML's engine); network.mjs caps SAE at 256 bytes.
    function utf8Length(text) {
        let bytes = 0;
        for (const char of text) {
            const code = char.codePointAt(0);
            bytes += code < 0x80 ? 1 : code < 0x800 ? 2 : code < 0x10000 ? 3 : 4;
        }
        return bytes;
    }
    function validSae(text) { return text.length > 0 && !/[\0\r\n]/.test(text) && utf8Length(text) <= 256 }

    onExpandedChanged: {
        pskText = "";
        pskFocused = false;
        // Pauses live reads to the Wi-Fi list while a password is being typed, so
        // the list does not jump under the user's hands (shell.qml honours this).
        controller.interacting = expanded ? "network.psk" : "";
    }
    onVisibleChanged: if (!visible) expanded = ""

    Label { objectName: "networkDown"; visible: !!page.model && !page.model.running; text: "NetworkManager is not running."; color: page.theme.warn; font.pixelSize: 13 }
    Label { visible: !page.model; text: "Reading connections…"; color: page.theme.dim; font.pixelSize: 13 }

    SettingsSection {
        visible: !!page.model?.running
        theme: page.theme
        title: "Wi-Fi"
        PanelRow {
            theme: page.theme
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label { text: "Wi-Fi"; color: page.theme.foreground; font.pixelSize: 13; font.weight: Font.Medium; Layout.fillWidth: true }
                Label { visible: !!page.radio.error; text: page.radio.error || ""; color: page.theme.dim; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                Label { visible: !!page.model?.running && !page.model.wifi.enabled; text: "Wi-Fi is off"; color: page.theme.dim; font.pixelSize: 12 }
            }
            PanelButton { objectName: "networkEditor"; theme: page.theme; text: "Advanced…"; onClicked: page.controller.action("networkEditor") }
            PanelSwitch {
                id: radioSwitch
                theme: page.theme
                objectName: "wifiRadio"
                visible: page.radio.value !== undefined && !!page.model?.wifi?.available
                checked: page.radio.value === true
                enabled: !page.controller.busy
                Accessible.name: "Wi-Fi"
                onToggled: page.controller.change("network.wifi", checked)
            }
        }
        Repeater {
            model: page.model?.running && page.model.wifi.enabled ? page.model.wifi.networks : []
            delegate: Item {
                id: entry
                required property var modelData
                readonly property bool secured: modelData.security === "psk" || modelData.security === "sae"
                readonly property bool askPassword: page.expanded === modelData.ssid
                readonly property string statusText: modelData.active ? "Connected" : modelData.activating ? "Connecting" : modelData.known ? "Saved" : ""
                readonly property string accessibleName: [modelData.ssid, modelData.bars + " of 4 bars",
                    (modelData.security === "open" || modelData.security === "owe") ? "open" : "secured"].concat(statusText ? [statusText] : []).join(", ")
                function activate() {
                    if (page.controller.busy || entry.modelData.activating) return;
                    if (entry.modelData.security === "unsupported" && !entry.modelData.known) return;
                    if (entry.modelData.active) return;
                    if (entry.modelData.known || !entry.secured) {
                        page.expanded = "";
                        page.controller.submit({op: "wifiConnect", ssid: entry.modelData.ssid});
                    } else page.expanded = entry.askPassword ? "" : entry.modelData.ssid;
                }
                objectName: "wifi-" + modelData.ssid
                Layout.fillWidth: true
                implicitHeight: Math.max(46, entryColumn.implicitHeight + 18)
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: entry.accessibleName
                Keys.onReturnPressed: entry.activate()
                Keys.onEnterPressed: entry.activate()
                Keys.onSpacePressed: entry.activate()
                Accessible.onPressAction: entry.activate()
                // Every network follows the Wi-Fi switch row, so each has a hairline.
                Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.leftMargin: 14; height: 1; color: page.theme.line }
                Rectangle {
                    anchors.fill: parent; anchors.margins: 3
                    radius: 8
                    color: rowArea.containsMouse && rowArea.enabled ? page.theme.tone(0.05) : "transparent"
                    border.width: entry.activeFocus ? 2 : 0
                    border.color: page.theme.accent
                }
                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !page.controller.busy && !entry.modelData.activating && (entry.modelData.security !== "unsupported" || entry.modelData.known)
                    onClicked: entry.activate()
                }
                ColumnLayout {
                    id: entryColumn
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.leftMargin: 14; anchors.rightMargin: 14; anchors.topMargin: 9
                    spacing: 8
                    RowLayout {
                        spacing: 10
                        Label { text: page.bars[entry.modelData.bars]; color: entry.modelData.active ? page.theme.accent : page.theme.foreground; font.pixelSize: 16 }
                        Label { text: entry.modelData.ssid; textFormat: Text.PlainText; color: page.theme.foreground; font.pixelSize: 13; font.weight: entry.modelData.active ? Font.DemiBold : Font.Normal; elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { visible: entry.modelData.security !== "open" && entry.modelData.security !== "owe"; text: page.lock; color: page.theme.dim }
                        Label { text: entry.statusText; color: page.theme.dim; font.pixelSize: 12 }
                        Loader {
                            active: entry.modelData.known
                            sourceComponent: PanelButton {
                                objectName: "forget-" + entry.modelData.ssid
                                theme: page.theme; text: "Forget"
                                Accessible.name: "Forget " + entry.modelData.ssid
                                enabled: !page.controller.busy
                                onClicked: page.controller.submit({op: "wifiForget", ssid: entry.modelData.ssid})
                            }
                        }
                        Loader {
                            // A known enterprise/WEP profile activates like any saved network;
                            // Advanced… is only for one we cannot offer to connect at all.
                            active: entry.modelData.security === "unsupported" && !entry.modelData.known
                            sourceComponent: PanelButton {
                                objectName: "advanced-" + entry.modelData.ssid
                                theme: page.theme; text: "Advanced…"
                                Accessible.name: "Advanced settings for " + entry.modelData.ssid
                                onClicked: page.controller.action("networkEditor")
                            }
                        }
                    }
                    Item {
                        visible: entry.askPassword
                        Layout.fillWidth: true
                        Layout.bottomMargin: 9
                        implicitWidth: pskRow.implicitWidth
                        implicitHeight: pskRow.implicitHeight
                        // Swallows clicks inside the password row (including a disabled Connect
                        // button, which is transparent to input) so they cannot fall through to
                        // the entry's own MouseArea and collapse the row out from under the user.
                        // A sibling of the RowLayout, not its child: anchors inside a layout are undefined.
                        MouseArea { objectName: "pskShield-" + entry.modelData.ssid; anchors.fill: parent; onClicked: {} }
                        RowLayout {
                            id: pskRow
                            anchors.left: parent.left; anchors.right: parent.right
                            PanelField {
                                id: psk
                                theme: page.theme
                                objectName: "psk-" + entry.modelData.ssid
                                Layout.fillWidth: true
                                echoMode: TextInput.Password
                                placeholderText: "Password"
                                text: page.pskText
                                Accessible.name: "Password for " + entry.modelData.ssid
                                onTextEdited: page.pskText = text
                                onActiveFocusChanged: page.pskFocused = activeFocus
                                Component.onCompleted: if (page.pskFocused) forceActiveFocus()
                                onAccepted: { if (connectButton.enabled) connectButton.clicked(); }
                            }
                            PanelButton {
                                id: connectButton
                                objectName: "connect-" + entry.modelData.ssid
                                theme: page.theme; primary: true; text: "Connect"
                                Accessible.name: "Connect " + entry.modelData.ssid
                                // WPA2 needs 8–63 characters (or 64 hex digits); WPA3-SAE accepts any
                                // non-empty password without line breaks (network.mjs validates both authoritatively).
                                enabled: (entry.modelData.security === "sae" ? page.validSae(page.pskText) : page.validPsk(page.pskText)) && !page.controller.busy
                                onClicked: {
                                    page.controller.submit({op: "wifiConnect", ssid: entry.modelData.ssid, psk: page.pskText});
                                    page.pskText = "";
                                    page.expanded = "";
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    SettingsSection {
        visible: !!page.model?.running && page.model.wired.length > 0
        theme: page.theme
        title: "Wired"
        Repeater {
            model: page.model?.running ? page.model.wired : []
            delegate: PanelRow {
                id: wired
                required property var modelData
                required property int index
                theme: page.theme
                divider: index > 0
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Label { text: wired.modelData.iface; color: page.theme.foreground; font.pixelSize: 13; font.weight: Font.Medium; Layout.fillWidth: true }
                    Label {
                        text: wired.modelData.carrier
                            ? wired.modelData.speed + " Mb/s · " + (wired.modelData.ip4 || "no address") + (wired.modelData.gateway ? " via " + wired.modelData.gateway : "")
                            : "Cable unplugged"
                        color: page.theme.dim; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true
                    }
                }
                Label { visible: !!wired.modelData.carrier; text: "Connected"; color: page.theme.dim; font.pixelSize: 12 }
            }
        }
    }

    SettingsSection {
        visible: !!page.model?.running && (page.model.vpn.length > 0 || !!page.model.proton)
        theme: page.theme
        title: "VPN"
        PanelRow {
            visible: !!page.model?.proton
            theme: page.theme
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                Label { text: "Proton VPN"; color: page.theme.foreground; font.pixelSize: 13; font.weight: Font.Medium; Layout.fillWidth: true }
                Label { text: page.model?.proton?.active ? "Connected · managed in its own app" : "Managed in its own app"; color: page.theme.dim; font.pixelSize: 12; Layout.fillWidth: true }
            }
            PanelButton { objectName: "protonApp"; theme: page.theme; text: "Open Proton VPN"; onClicked: page.controller.action("protonApp") }
        }
        Repeater {
            model: page.model?.running ? page.model.vpn : []
            delegate: PanelRow {
                id: vpnRow
                required property var modelData
                required property int index
                theme: page.theme
                divider: index > 0 || !!page.model?.proton
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Label { text: vpnRow.modelData.name; textFormat: Text.PlainText; color: page.theme.foreground; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight; Layout.fillWidth: true }
                    Label {
                        text: vpnRow.modelData.state === "activated" ? "Connected" + (vpnRow.modelData.iface ? " on " + vpnRow.modelData.iface : "")
                            : vpnRow.modelData.state === "activating" ? "Connecting…" : "Off"
                        color: page.theme.dim; font.pixelSize: 12
                    }
                }
                Loader {
                    active: vpnRow.modelData.control === "switch"
                    sourceComponent: PanelSwitch {
                        theme: page.theme
                        objectName: "vpn-" + vpnRow.modelData.uuid
                        checked: vpnRow.modelData.state !== "off"
                        enabled: !page.controller.busy
                        Accessible.name: vpnRow.modelData.name
                        onToggled: page.controller.submit({op: "vpn", uuid: vpnRow.modelData.uuid, active: checked})
                    }
                }
            }
        }
    }
}
