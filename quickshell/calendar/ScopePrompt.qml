pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// A small dialog over the sheet: a question and a column of choices
// ({value, label, danger}), plus Cancel. The sheet behind is dimmed so the
// question is the only thing to read. Esc or a click on the dimmed sheet cancels.
Rectangle {
    id: prompt
    required property var card
    property string question: ""
    property var choices: []
    signal chosen(string value)
    signal cancelled()
    anchors.fill: parent
    z: 30
    color: Qt.rgba(card.c.background.r, card.c.background.g, card.c.background.b, 0.86)
    radius: card.px(12)
    MouseArea { anchors.fill: parent; onClicked: prompt.cancelled() }
    Keys.onEscapePressed: event => { prompt.cancelled(); event.accepted = true; }
    onVisibleChanged: if (visible) { forceActiveFocus(); pop.restart(); }
    Rectangle {
        id: dialog
        anchors.centerIn: parent
        width: parent.width - prompt.card.px(40)
        height: col.implicitHeight + prompt.card.px(32)
        radius: prompt.card.px(14)
        color: Qt.rgba(prompt.card.c.background.r * 1.6, prompt.card.c.background.g * 1.6, prompt.card.c.background.b * 1.6, 1)
        border.width: 1
        border.color: Qt.rgba(prompt.card.c.foreground.r, prompt.card.c.foreground.g, prompt.card.c.foreground.b, 0.16)
        MouseArea { anchors.fill: parent }        // a click inside is not a cancel
        ParallelAnimation {
            id: pop
            NumberAnimation { target: dialog; property: "scale"; from: 0.96; to: 1; duration: 160; easing.type: Easing.OutCubic }
            NumberAnimation { target: dialog; property: "opacity"; from: 0; to: 1; duration: 120; easing.type: Easing.OutCubic }
        }
        ColumnLayout {
            id: col
            x: prompt.card.px(16); y: prompt.card.px(16)
            width: parent.width - prompt.card.px(32)
            spacing: prompt.card.px(8)
            Text { objectName: "promptQuestion"; Layout.fillWidth: true; Layout.bottomMargin: prompt.card.px(4)
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: prompt.question; color: prompt.card.c.foreground; font.family: prompt.card.c.monoFont
                font.pixelSize: prompt.card.px(14); font.weight: Font.DemiBold }
            Repeater {
                model: prompt.choices
                delegate: Rectangle {
                    id: choice
                    required property var modelData
                    required property int index
                    objectName: "choice" + index
                    Layout.fillWidth: true; implicitHeight: prompt.card.px(34); radius: prompt.card.px(10)
                    readonly property color base: modelData.danger ? "#c2484b" : prompt.card.c.accent
                    color: Qt.lighter(base, choiceHover.containsMouse ? 1.12 : 1)
                    Text { anchors.centerIn: parent; text: choice.modelData.label; font.weight: Font.Bold
                        color: choice.modelData.danger ? "#ffffff" : prompt.card.c.accentInk
                        font.family: prompt.card.c.monoFont; font.pixelSize: prompt.card.px(13) }
                    MouseArea { id: choiceHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: prompt.chosen(choice.modelData.value) }
                }
            }
            Rectangle {
                objectName: "promptCancel"
                Layout.fillWidth: true; implicitHeight: prompt.card.px(34); radius: prompt.card.px(10)
                color: Qt.rgba(prompt.card.c.foreground.r, prompt.card.c.foreground.g, prompt.card.c.foreground.b, cancelHover.containsMouse ? 0.14 : 0.08)
                Text { anchors.centerIn: parent; text: "Cancel"; color: prompt.card.c.foreground
                    font.family: prompt.card.c.monoFont; font.pixelSize: prompt.card.px(13) }
                MouseArea { id: cancelHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: prompt.cancelled() }
            }
        }
    }
}
