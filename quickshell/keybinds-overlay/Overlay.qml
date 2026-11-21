pragma ComponentBehavior: Bound
import QtQuick
import "sheet.mjs" as Sheet

// The full-screen HUD. It is read-only: typing filters, the wheel scrolls only
// when the grid overflows, and Esc or any click closes.
Item {
    id: view
    required property var controller

    readonly property color background: controller.background
    readonly property color foreground: controller.foreground
    readonly property color accent: Sheet.readableAccent(String(controller.accent), String(controller.background), String(controller.foreground))
    readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.62)
    readonly property color raised: Qt.tint(background, Qt.rgba(foreground.r, foreground.g, foreground.b, 0.09))
    readonly property color line: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
    readonly property string monoFont: controller.monoFont

    // Every size below is a 1080p size times uiScale, so the sheet reads at
    // the same physical size on a 1440p panel instead of shrinking with it.
    // Taken from the height a 16:9 output of this width would have, when that
    // is smaller, so a portrait output does not scale up into narrow columns.
    readonly property real uiScale: Math.max(1, Math.min(1.6, Math.min(height, width * 9 / 16) / 1000))
    function px(size) {
        return Math.round(size * uiScale);
    }

    readonly property int sideMargin: px(44)
    readonly property int columnGap: px(28)
    readonly property var shown: Sheet.filterSheet(controller.sheet, controller.query)
    readonly property int total: Sheet.countRows(controller.sheet)
    readonly property int shownCount: Sheet.countRows(shown)
    readonly property int columns: Sheet.columnCount(width - 2 * sideMargin, px(Sheet.COLUMN_WIDTH))
    readonly property var layout: Sheet.distribute(shown, columns)
    readonly property real columnWidth: (Math.min(width - 2 * sideMargin, columns * px(480)) - (columns - 1) * columnGap) / columns
    // Section geometry, shared with SectionBlock so the height estimate below
    // cannot drift from what is drawn.
    readonly property int rowHeight: px(26)
    readonly property int headingHeight: px(32)
    readonly property int sectionGap: px(18)
    // The unfiltered grid's height. The prompt and grid sit as one block
    // centred on it, so typing narrows the results under a prompt that stays
    // put instead of moving it, or leaving the results mid-screen.
    readonly property real fullHeight: Sheet.distribute(controller.sheet, columns).reduce((tallest, column) => Math.max(tallest, column.reduce((h, s) => h + headingHeight + rowHeight * s.rows.length, 0) + sectionGap * Math.max(0, column.length - 1)), 0)
    readonly property real composedTop: Math.max(px(34), (height - px(40) - px(26) - fullHeight - px(60)) / 2)

    focus: true
    opacity: 0
    Component.onCompleted: opacity = 1
    Behavior on opacity {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    // A new filter starts at the top: an old scroll offset would hide the
    // first matches above the viewport.
    Connections {
        target: view.controller
        function onQueryChanged() {
            flick.scrollTarget = 0;
            flick.contentY = 0;
        }
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        const query = view.controller.query;
        if (event.key === Qt.Key_Escape) {
            view.controller.close();
        } else if (event.key === Qt.Key_Backspace) {
            view.controller.query = ctrl ? "" : query.slice(0, -1);
        } else if (ctrl && event.key === Qt.Key_U) {
            view.controller.query = "";
        } else if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) && event.text.length === 1 && event.text >= " " && event.text !== "\x7f") {
            view.controller.query = query + event.text;
        } else {
            return;
        }
        event.accepted = true;
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(view.background.r, view.background.g, view.background.b, 0.78)
    }

    // Above everything: any click closes, and the wheel moves the grid by
    // pixels. The Flickable itself is not interactive, so it never swallows
    // the click.
    MouseArea { // a11y: not a control
        anchors.fill: parent
        z: 10
        acceptedButtons: Qt.AllButtons
        onClicked: view.controller.close()
        // Steps accumulate on scrollTarget, not on the animated contentY, so a
        // fast wheel or touchpad stream keeps its full distance.
        onWheel: wheel => {
            const step = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y;
            const max = Math.max(0, flick.contentHeight - flick.height);
            flick.scrollTarget = Math.max(0, Math.min(max, Math.min(flick.scrollTarget, max) - step));
            flick.contentY = flick.scrollTarget;
        }
    }

    Item {
        id: promptBar
        anchors.top: parent.top
        anchors.topMargin: view.composedTop
        anchors.horizontalCenter: parent.horizontalCenter
        // Only the text is centred: the caret and the count hang off its right
        // edge, so they appear without shifting it.
        width: promptText.width
        height: view.px(40)
        Text {
                id: promptText
                objectName: "prompt"
                // A very long query keeps its newest characters in view
                // instead of running off the output.
                width: Math.min(implicitWidth, view.width * 0.6)
                elide: Text.ElideLeft
                anchors.verticalCenter: parent.verticalCenter
                text: view.controller.query === "" ? "Type to filter keybindings" : view.controller.query
                font.pixelSize: view.px(26)
                font.weight: Font.Light
                color: view.controller.query === "" ? view.dim : view.foreground
            }
            Rectangle {
                anchors.left: promptText.right
                anchors.leftMargin: view.px(4)
                anchors.verticalCenter: parent.verticalCenter
                visible: view.controller.query !== ""
                width: Math.max(2, view.px(2))
                height: view.px(28)
                color: view.foreground
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: view.controller.query !== ""
                    NumberAnimation { to: 0; duration: 530 }
                    NumberAnimation { to: 1; duration: 530 }
                }
            }
            Text {
                objectName: "count"
                anchors.left: promptText.right
                anchors.leftMargin: view.px(20)
                anchors.verticalCenter: parent.verticalCenter
                visible: view.controller.query !== ""
                text: view.shownCount + " of " + view.total
                font.pixelSize: view.px(13)
                color: view.dim
            }
    }

    Flickable {
        id: flick
        objectName: "flick"
        anchors.top: promptBar.bottom
        anchors.topMargin: view.px(26)
        anchors.bottom: footer.top
        anchors.bottomMargin: view.px(14)
        anchors.left: parent.left
        anchors.right: parent.right
        property real scrollTarget: 0
        interactive: false
        clip: true
        contentWidth: width
        contentHeight: grid.implicitHeight
        Behavior on contentY {
            NumberAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }

        Row {
            id: grid
            objectName: "grid"
            visible: view.controller.problem === "" && !view.controller.loading && view.shown.length > 0
            x: (flick.width - implicitWidth) / 2
            spacing: view.columnGap
            Repeater {
                model: view.layout
                delegate: Column {
                    id: column
                    required property var modelData
                    width: view.columnWidth
                    spacing: view.sectionGap
                    Repeater {
                        model: column.modelData
                        delegate: SectionBlock {
                            required property var modelData
                            width: column.width
                            section: modelData
                            theme: view
                            query: view.controller.query
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        visible: flick.contentHeight > flick.height
        anchors.right: parent.right
        anchors.rightMargin: view.px(6)
        y: flick.y + flick.contentY / flick.contentHeight * flick.height
        width: view.px(4)
        height: Math.max(view.px(24), flick.height * flick.height / flick.contentHeight)
        radius: width / 2
        color: Qt.rgba(view.foreground.r, view.foreground.g, view.foreground.b, 0.25)
    }

    Text {
        objectName: "empty"
        anchors.centerIn: flick
        visible: view.controller.problem === "" && !view.controller.loading && view.controller.query !== "" && view.shown.length === 0
        text: "No keybinding matches “" + view.controller.query + "”"
        font.pixelSize: view.px(15)
        color: view.dim
    }
    Text {
        objectName: "problem"
        anchors.centerIn: flick
        width: Math.min(view.px(640), view.width - 2 * view.sideMargin)
        visible: view.controller.problem !== ""
        text: view.controller.problem
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: view.px(15)
        color: view.foreground
        Accessible.role: Accessible.AlertMessage
    }

    Row {
        id: footer
        anchors.bottom: parent.bottom
        anchors.bottomMargin: view.px(22)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: view.px(6)
        Keycap {
            anchors.verticalCenter: parent.verticalCenter
            keyName: "Esc"
            theme: view
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "close  ·  any key filters"
            font.pixelSize: view.px(11)
            color: view.dim
        }
    }
}
