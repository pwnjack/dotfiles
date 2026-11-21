import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// The window a bar card opens in (media, sound, updates, weather): it covers the
// output below (or above) the bar, closes on a click outside the card, puts
// the card under the clicked point of the bar and runs its entrance and
// leave. The card is its one child, with `focus: true`.
// Quickshell loads QML only from a config's own folder: each card links this
// file into its directory.
//   controller  opened, closing, cursorX (global, NaN when unknown),
//               barAtBottom, uiScale, close()
PanelWindow {
    id: window
    required property var controller
    required property string namespace
    // Where the card centres when the cursor is unknown.
    property real fallbackX: width
    default property alias content: holder.data
    signal appeared()
    signal leaving()

    function px(size) { return Math.round(size * controller.uiScale); }
    function pickScreen() {
        const focused = Hyprland.focusedMonitor;
        screen = Quickshell.screens.find(s => focused && s.name === focused.name) || Quickshell.screens[0];
    }
    function appear() {
        leave.stop();
        enter.start();
        holder.forceActiveFocus();
        appeared();
    }
    function disappear() {
        leaving();
        enter.stop();
        leave.start();
    }

    visible: controller.opened || controller.closing
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    // Normal: respect Waybar's exclusive zone, so the window starts just
    // below (or above) the bar and the card sits a gap away from it.
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.namespace: window.namespace
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: controller.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: window.controller.close() }

    FocusScope {
        id: holder
        focus: true
        enabled: window.controller.opened
        visible: window.controller.opened || window.controller.closing
        width: childrenRect.width
        height: childrenRect.height
        readonly property int edge: window.px(12)
        readonly property real anchorX: isFinite(window.controller.cursorX)
            ? window.controller.cursorX - (window.screen ? window.screen.x : 0) : window.fallbackX
        x: Math.max(edge, Math.min(window.width - width - edge, anchorX - width / 2))
        y: window.controller.barAtBottom ? window.height - height - window.px(8) : window.px(8)

        // The mockup's entrance: fade over 180 ms while scaling from 97% and
        // dropping 8 px over 220 ms, from the clicked point of the bar.
        property real fade: 0
        property real lift: 0
        opacity: fade
        transform: [
            Scale {
                origin.x: Math.max(0, Math.min(holder.width, holder.anchorX - holder.x))
                origin.y: window.controller.barAtBottom ? holder.height : 0
                xScale: 0.97 + 0.03 * holder.lift
                yScale: 0.97 + 0.03 * holder.lift
            },
            Translate { y: (window.controller.barAtBottom ? 1 : -1) * window.px(8) * (1 - holder.lift) }
        ]
    }
    ParallelAnimation {
        id: enter
        NumberAnimation { target: holder; property: "fade"; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: holder; property: "lift"; to: 1; duration: 220; easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: leave
        NumberAnimation { target: holder; property: "fade"; to: 0; duration: 140; easing.type: Easing.InCubic }
        NumberAnimation { target: holder; property: "lift"; to: 0; duration: 140; easing.type: Easing.InCubic }
        onFinished: if (window.controller.closing) Qt.quit()
    }
}
