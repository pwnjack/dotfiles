pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

FocusScope {
    id: view
    required property var controller
    required property real pixelScale
    readonly property WallpaperCard currentCard: cards.currentItem as WallpaperCard
    readonly property real margin: Math.max(24, width * 0.045)
    focus: true
    Component.onCompleted: forceActiveFocus()
    Binding {
        target: view.controller
        property: "previewReady"
        value: !!view.currentCard?.ready
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            view.controller.close();
        } else if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
            view.controller.searchVisible = true;
            search.forceActiveFocus();
        } else if (event.key === Qt.Key_Left && !search.activeFocus) {
            view.controller.navigate(-1);
        } else if (event.key === Qt.Key_Right && !search.activeFocus) {
            view.controller.navigate(1);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (view.currentCard?.ready)
                view.controller.confirm();
        } else {
            return;
        }
        event.accepted = true;
    }
    Rectangle {
        anchors.fill: parent
        // Light tint over Hyprland's live compositor blur.
        color: Qt.alpha(view.controller.background, 0.24)
    }
    Column {
        x: view.margin
        y: Math.max(28, view.height * 0.08)
        spacing: 12
        Text {
            text: "YOUR COLLECTION"
            color: view.controller.foreground
            opacity: 0.65
            font.family: "sans-serif"
            font.pixelSize: 12
            font.letterSpacing: 3
        }
        Text {
            text: "Wallpapers"
            color: view.controller.foreground
            font.family: "sans-serif"
            font.pixelSize: Math.min(48, view.height * 0.05)
            font.weight: Font.DemiBold
        }
    }
    Row {
        anchors.right: parent.right
        anchors.rightMargin: view.margin
        y: Math.max(28, view.height * 0.09)
        spacing: 12
        ActionButton {
            text: "Search"
            theme: view.controller
            onClicked: {
                view.controller.searchVisible = !view.controller.searchVisible;
                if (view.controller.searchVisible)
                    search.forceActiveFocus();
            }
        }
        ActionButton {
            text: "Close"
            theme: view.controller
            onClicked: view.controller.close()
        }
    }
    TextField {
        id: search
        objectName: "filenameSearch"
        anchors.horizontalCenter: parent.horizontalCenter
        y: view.height * 0.20
        width: Math.min(520, view.width - 2 * view.margin)
        height: 48
        visible: view.controller.searchVisible
        placeholderText: "Search by filename…"
        text: view.controller.query
        onTextEdited: view.controller.query = text
        color: view.controller.foreground
        placeholderTextColor: Qt.alpha(view.controller.foreground, 0.6)
        selectionColor: view.controller.accent
        font.family: "sans-serif"
        font.pixelSize: 16
        leftPadding: 20
        Accessible.name: "Search wallpapers by filename"
        background: Rectangle {
            radius: 24
            color: view.controller.background
            border.color: search.activeFocus ? view.controller.accent : Qt.alpha(view.controller.foreground, 0.3)
            border.width: 2
        }
        Keys.onEscapePressed: view.controller.close()
        Keys.onReturnPressed: {
            view.forceActiveFocus();
        }
        Keys.onDownPressed: view.forceActiveFocus()
    }
    ListView {
        id: cards
        objectName: "wallpaperCards"
        x: 0
        y: view.height * 0.28
        width: view.width
        height: view.height * 0.47
        orientation: ListView.Horizontal
        model: view.controller.loading ? [] : view.controller.entries
        onModelChanged: Qt.callLater(() => {
            forceLayout();
            positionViewAtIndex(view.controller.selectedIndex, ListView.Center);
        })
        currentIndex: view.controller.selectedIndex
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (width - delegateWidth) / 2
        preferredHighlightEnd: preferredHighlightBegin
        readonly property real delegateWidth: Math.min(620, view.width * 0.30)
        highlightMoveDuration: view.controller.reducedMotion ? 0 : 260
        highlightMoveVelocity: -1
        // Navigation is discrete, so kinetic scrolling cannot desynchronize selection.
        interactive: false
        cacheBuffer: delegateWidth
        clip: false
        delegate: WallpaperCard {
            id: card
            required property var modelData
            required property int index
            width: cards.delegateWidth
            height: cards.height
            imageUrl: card.modelData.url
            title: card.modelData.name
            selected: card.index === view.controller.selectedIndex
            reducedMotion: view.controller.reducedMotion
            pixelScale: view.pixelScale
            accent: view.controller.accent
            onClicked: {
                if (view.controller.submitting)
                    return;
                if (card.selected && card.ready)
                    view.controller.confirm();
                else {
                    view.controller.selectedIndex = card.index;
                    view.forceActiveFocus();
                }
            }
        }
    }
    Column {
        anchors.centerIn: cards
        width: Math.min(640, view.width - 2 * view.margin)
        spacing: 14
        visible: view.controller.loading || !view.controller.entries.length
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: view.controller.loading ? "Finding your wallpapers…" : view.controller.query ? "No matching wallpapers" : "No wallpapers here yet"
            color: view.controller.foreground
            font.family: "sans-serif"
            font.pixelSize: 28
        }
        Text {
            width: parent.width
            text: view.controller.query ? "Try a different filename, or press Esc to close." : "Choose your wallpaper folder in Waypaper. Press Esc to return to the desktop."
            visible: !view.controller.loading
            color: view.controller.foreground
            opacity: 0.7
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.family: "sans-serif"
            font.pixelSize: 16
        }
    }
    Column {
        y: view.height * 0.78
        anchors.horizontalCenter: parent.horizontalCenter
        width: view.width - 2 * view.margin
        spacing: 10
        Text {
            width: parent.width
            text: view.controller.selected?.name || ""
            textFormat: Text.PlainText
            color: view.controller.foreground
            font.family: "sans-serif"
            font.pixelSize: 22
            font.weight: Font.Medium
            elide: Text.ElideMiddle
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            width: parent.width
            text: view.controller.submitting ? "Applying wallpaper and colors…" : view.controller.entries.length ? (view.controller.selectedIndex + 1) + " / " + view.controller.entries.length + "   ·   " + (view.controller.selected?.path === view.controller.snapshot.current ? "Current wallpaper" : "Apply to all monitors") : ""
            color: view.controller.foreground
            opacity: 0.65
            font.family: "sans-serif"
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            width: parent.width
            text: view.controller.problem
            textFormat: Text.PlainText
            visible: text.length > 0
            color: view.controller.foreground
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.family: "sans-serif"
            font.pixelSize: 14
            Accessible.role: Accessible.AlertMessage
        }
    }
    Row {
        x: view.margin
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28
        spacing: 12
        ActionButton {
            text: "←"
            Accessible.name: "Previous wallpaper"
            theme: view.controller
            enabled: !view.controller.submitting && view.controller.entries.length > 0
            onClicked: view.controller.navigate(-1)
        }
        ActionButton {
            text: "→"
            Accessible.name: "Next wallpaper"
            theme: view.controller
            enabled: !view.controller.submitting && view.controller.entries.length > 0
            onClicked: view.controller.navigate(1)
        }
        Text {
            height: 46
            verticalAlignment: Text.AlignVCenter
            text: "← →  Browse     Ctrl+F  Search"
            color: view.controller.foreground
            opacity: 0.65
            font.family: "sans-serif"
            font.pixelSize: 13
            visible: view.width > 800
        }
    }
    ActionButton {
        anchors.right: parent.right
        anchors.rightMargin: view.margin
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28
        objectName: "applyWallpaper"
        text: view.controller.submitting ? "Applying…" : "Apply wallpaper   ↵"
        theme: view.controller
        enabled: !view.controller.loading && !view.controller.submitting && !!view.currentCard?.ready
        onClicked: view.controller.confirm()
    }
    MouseArea {
        id: scrolling
        anchors.fill: parent
        // Capture wheels anywhere, but let card/button clicks and hover pass through.
        acceptedButtons: Qt.NoButton
        scrollGestureEnabled: true
        property real pendingSteps: 0
        onWheel: wheel => {
            wheel.accepted = true;
            if (view.controller.loading || view.controller.submitting)
                return;
            const pixels = wheel.pixelDelta.y || wheel.pixelDelta.x;
            const angle = wheel.angleDelta.y || wheel.angleDelta.x;
            const delta = pixels ? pixels / 40 : angle / 120;
            if (pendingSteps * delta < 0)
                pendingSteps = 0;
            pendingSteps += delta;
            const steps = Math.trunc(pendingSteps);
            if (steps) {
                view.controller.navigate(-steps);
                pendingSteps -= steps;
            }
            wheelReset.restart();
        }
        Timer {
            id: wheelReset
            interval: 250
            onTriggered: scrolling.pendingSteps = 0
        }
    }
}
