pragma ComponentBehavior: Bound
import QtQuick
import "model.mjs" as Model

// The update card (docs/updates.md).
// One translucent frame whose height follows the active view; views
// crossfade; the progress value glides here so every view sees one number.
FocusScope {
    id: card
    required property var controller

    function px(size) { return Math.round(size * controller.uiScale); }
    readonly property color background: controller.background
    readonly property color foreground: controller.foreground
    readonly property color accent: controller.accent
    readonly property color accentInk: controller.accentInk
    readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.62)
    readonly property color hairline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
    // Fixed amber keeps warnings distinct from the wallpaper accent.
    readonly property color warn: "#e3a857"
    readonly property color warnInk: "#1a1206"
    readonly property string monoFont: controller.monoFont
    readonly property string mode: controller.mode
    readonly property var result: mode === "result" && controller.run ? Model.result(controller.run) : null
    readonly property Item activeView: mode === "running" ? progressView : mode === "result" ? resultView : summaryView

    // The displayed progress. shell.qml sets it directly when it opens on a
    // run already under way, so a reopened card resumes where the run is.
    property real shown: 0
    FrameAnimation {
        running: card.mode !== "summary"
        onTriggered: {
            const run = card.controller.run;
            const target = run && typeof run.progress === "number" ? run.progress : 0;
            card.shown = Model.glide(card.shown, target, frameTime);
        }
    }

    // Return, Enter and Space do nothing for this long after a view becomes
    // active. Results and the plan arrive while the card holds keyboard focus,
    // so a Return meant for another window must not press Restart or Update.
    // Mouse clicks are not guarded.
    readonly property int activationDelay: 1000
    property double armedAt: 0
    function armKeys() { armedAt = Date.now() + activationDelay; }
    function keysArmed() { return Date.now() >= armedAt; }
    onActiveViewChanged: armKeys()
    Component.onCompleted: armKeys()

    function focusPrimary() { activeView.focusPrimary(); }
    onModeChanged: {
        if (mode === "summary") shown = 0;
        Qt.callLater(focusPrimary);
    }
    Keys.onEscapePressed: controller.close()
    // Return anywhere on the summary starts the update, as in the mockup;
    // a focused button handles its own Return first.
    function activate() {
        if (keysArmed() && mode === "summary" && summaryView.canUpdate) controller.start();
    }
    Keys.onReturnPressed: activate()
    Keys.onEnterPressed: activate()

    width: px(372)
    height: frame.height

    Rectangle {
        id: frame
        width: parent.width
        height: card.activeView.implicitHeight + card.px(34)
        // Eases between views. While the package list animates, the content
        // height already moves every frame: a Behavior would restart on each
        // step and trail the list, so the frame follows it directly instead.
        Behavior on height {
            enabled: !(card.activeView === summaryView && summaryView.resizing)
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
        }
        radius: card.px(18)
        color: Qt.rgba(card.background.r, card.background.g, card.background.b, 0.68)
        border.width: 1
        border.color: card.result && card.result.tone === "warn"
            ? Qt.rgba(card.warn.r, card.warn.g, card.warn.b, 0.55)
            : Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.22)
        Behavior on border.color { ColorAnimation { duration: 200 } }
        clip: true

        // Clicks inside the card never reach the close-on-outside-click area.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        SummaryView {
            id: summaryView
            card: card
            controller: card.controller
            x: card.px(18); y: card.px(18); width: parent.width - card.px(36)
            opacity: card.activeView === summaryView ? 1 : 0
            // Visible at once when it becomes active, so it can take focus while fading in.
            visible: opacity > 0 || card.activeView === summaryView
            enabled: card.activeView === summaryView
            Behavior on opacity { NumberAnimation { duration: 140 } }
        }
        ProgressView {
            id: progressView
            card: card
            controller: card.controller
            x: card.px(18); y: card.px(18); width: parent.width - card.px(36)
            opacity: card.activeView === progressView ? 1 : 0
            // Visible at once when it becomes active, so it can take focus while fading in.
            visible: opacity > 0 || card.activeView === progressView
            enabled: card.activeView === progressView
            Behavior on opacity { NumberAnimation { duration: 140 } }
        }
        ResultView {
            id: resultView
            card: card
            controller: card.controller
            x: card.px(18); y: card.px(18); width: parent.width - card.px(36)
            opacity: card.activeView === resultView ? 1 : 0
            // Visible at once when it becomes active, so it can take focus while fading in.
            visible: opacity > 0 || card.activeView === resultView
            enabled: card.activeView === resultView
            Behavior on opacity { NumberAnimation { duration: 140 } }
        }
    }
}
