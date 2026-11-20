import QtQuick
import QtQuick.Controls

// The strip's tooltip, shared by its tabs, controls and action button.
ToolTip {
    id: tip
    required property var strip
    popupType: Popup.Item
    delay: 600
    contentItem: Text {
        // contentItem is reparented to the popup: name the tip, not parent.
        text: tip.text
        color: tip.strip.foreground
        font.family: tip.strip.monoFont
        font.pixelSize: tip.strip.px(12)
    }
    background: Rectangle {
        color: tip.strip.background
        radius: tip.strip.px(6)
        border.color: tip.strip.hairline
    }
}
