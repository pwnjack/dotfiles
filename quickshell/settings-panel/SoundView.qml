pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The audio devices the sound popover lists: a name for each and a switch for whether it
// shows there. shell.qml re-reads soundDevices while the Sound page is on screen. The
// "Output" and "Input" sections above come from catalog.json like any other section.
SettingsSection {
    id: page
    required property var controller
    objectName: "soundView"
    title: "Devices"
    footer: "Hidden devices are left out of the sound popover. Nothing is disabled."
    // The Repeater draws this array, not controller.sound: replacing a Repeater's array rebuilds its
    // delegates and wipes typed text, so a reply that lands while a name is being edited is held and
    // drawn once that field lets go.
    property var entries: []
    property string editing: ""
    property bool held: false
    readonly property var sound: controller.sound
    function build() {
        const sound = page.sound;
        if (!sound) return [];
        const tagged = (devices, tag) => (devices || []).map(device => ({ device: device, tag: device.virtual ? "Virtual" : tag,
            inUse: device.name === (tag === "Mic" ? sound.defaultSource : sound.defaultSink) }));
        return tagged(sound.outputs, "Speaker").concat(tagged(sound.inputs, "Mic"));
    }
    function sync() {
        if (page.editing) { page.held = true; return; }
        page.held = false;
        page.entries = page.build();
    }
    onSoundChanged: sync()
    onEditingChanged: if (!editing && held) sync()
    Component.onCompleted: sync()

    PanelRow {
        visible: !page.sound
        theme: page.theme
        Label { text: "Reading devices…"; color: page.theme.dim; font.pixelSize: 13 }
    }
    PanelRow {
        visible: !!page.sound && !page.entries.length
        theme: page.theme
        Label { text: "No audio devices found."; color: page.theme.dim; font.pixelSize: 13 }
    }
    Repeater {
        model: page.entries
        delegate: PanelRow {
            id: line
            required property var modelData
            required property int index
            readonly property var device: modelData.device
            readonly property bool changed: name.text.trim() !== device.custom
            theme: page.theme
            divider: index > 0
            Label {
                objectName: "soundTag-" + line.device.name
                text: line.modelData.tag
                color: page.theme.dim
                font.pixelSize: 12
                Layout.preferredWidth: 52
            }
            Item { Layout.fillWidth: true }
            PanelButton {
                objectName: "soundApply-" + line.device.name
                theme: page.theme
                primary: true
                text: "Apply"
                visible: line.changed
                onClicked: line.apply()
            }
            PanelField {
                id: name
                objectName: "soundName-" + line.device.name
                theme: page.theme
                Layout.preferredWidth: 240
                placeholderText: line.device.label
                text: line.device.custom
                pending: line.changed
                Accessible.name: line.device.description
                onAccepted: if (line.changed) line.apply()
                onActiveFocusChanged: {
                    if (activeFocus) page.editing = line.device.name;
                    else if (page.editing === line.device.name) page.editing = "";
                }
            }
            Item {
                implicitWidth: toggle.implicitWidth; implicitHeight: toggle.implicitHeight
                PanelSwitch {
                    id: toggle
                    objectName: "show-" + line.device.name
                    theme: page.theme
                    checked: line.device.shown
                    // The current device has to stay in the popover, so it cannot be hidden.
                    enabled: !line.modelData.inUse
                    onToggled: page.controller.soundRequest({ op: "soundShow", name: line.device.name, shown: checked })
                }
                MouseArea {
                    id: tipArea
                    anchors.fill: parent
                    enabled: !toggle.enabled
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    ToolTip {
                        popupType: Popup.Item
                        visible: tipArea.containsMouse
                        delay: 600
                        text: "In use"
                        contentItem: Text { text: "In use"; color: page.theme.foreground; font.pixelSize: 12 }
                        background: Rectangle { color: page.theme.raised; radius: 6; border.color: page.theme.line }
                    }
                }
            }
            function apply() { page.controller.soundRequest({ op: "soundName", name: device.name, label: name.text }); }
        }
    }
}
