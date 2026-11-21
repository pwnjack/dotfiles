import QtQuick

// One strip control from the mockup: a Nerd Font glyph over a short label.
// `on` paints the selected target or an enabled toggle. A click only emits
// `clicked`: targets select and toggles flip, nothing here starts a capture.
Rectangle {
    id: button
    required property var strip
    property int glyph: 0
    property string label: ""
    property string tip: ""
    property bool on: false
    // Targets and toggles are checkable; the close button (no label) is not.
    property bool checkable: label !== ""
    property int baseWidth: 52
    signal clicked()

    width: strip.px(baseWidth)
    height: strip.px(62)
    radius: strip.px(9)
    color: on ? Qt.rgba(strip.accent.r, strip.accent.g, strip.accent.b, 0.22)
        : mouse.containsMouse ? Qt.rgba(strip.foreground.r, strip.foreground.g, strip.foreground.b, 0.08)
        : "transparent"
    border.width: 1
    border.color: on ? Qt.rgba(strip.accent.r, strip.accent.g, strip.accent.b, 0.7) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }
    Accessible.role: Accessible.Button
    Accessible.name: label || tip
    Accessible.checkable: checkable
    Accessible.checked: on
    Accessible.onPressAction: if (enabled) clicked()

    Column {
        anchors.centerIn: parent
        spacing: button.strip.px(4)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: String.fromCodePoint(button.glyph)
            Accessible.ignored: true
            color: button.strip.foreground
            font.family: button.strip.monoFont
            font.pixelSize: button.strip.px(button.label ? 21 : 16)
        }
        Text {
            objectName: "label"
            visible: button.label !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, button.width - button.strip.px(4))
            elide: Text.ElideRight
            text: button.label
            Accessible.ignored: true
            color: button.strip.foreground
            opacity: 0.85
            font.family: button.strip.monoFont
            font.pixelSize: button.strip.px(11)
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
    StripTip { strip: button.strip; visible: mouse.containsMouse && button.tip !== ""; text: button.tip }
}
