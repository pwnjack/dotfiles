pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// A small centred prompt over the sheet: a question and a column of choices
// ({value, label, danger}), plus Cancel. Esc cancels.
Rectangle {
    id: prompt
    required property var card
    property string question: ""
    property var choices: []
    signal chosen(string value)
    signal cancelled()
    anchors.fill: parent
    z: 30
    color: Qt.rgba(card.c.background.r, card.c.background.g, card.c.background.b, 0.72)
    radius: card.px(18)
    MouseArea { anchors.fill: parent }
    Keys.onEscapePressed: event => { prompt.cancelled(); event.accepted = true; }
    onVisibleChanged: if (visible) forceActiveFocus()
    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width - prompt.card.px(48)
        spacing: prompt.card.px(8)
        Text { objectName: "promptQuestion"; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: prompt.question; color: prompt.card.c.foreground; font.family: prompt.card.c.monoFont
            font.pixelSize: prompt.card.px(14); font.weight: Font.DemiBold }
        Repeater {
            model: prompt.choices
            delegate: Rectangle {
                required property var modelData
                required property int index
                objectName: "choice" + index
                Layout.fillWidth: true; implicitHeight: prompt.card.px(34); radius: prompt.card.px(10)
                color: modelData.danger ? "#c2484b" : prompt.card.c.accent
                Text { anchors.centerIn: parent; text: modelData.label; font.weight: Font.Bold
                    color: modelData.danger ? "#ffffff" : prompt.card.c.accentInk
                    font.family: prompt.card.c.monoFont; font.pixelSize: prompt.card.px(13) }
                MouseArea { anchors.fill: parent; onClicked: prompt.chosen(modelData.value) }
            }
        }
        Text { Layout.alignment: Qt.AlignHCenter; text: "Cancel"; color: prompt.card.c.accent
            font.family: prompt.card.c.monoFont; font.pixelSize: prompt.card.px(13)
            MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: prompt.cancelled() } }
    }
}
