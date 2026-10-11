pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "model.mjs" as Model

// A month: ‹ name ›, localised weekday row, 6×7 days with event dots.
// `selected` rings a day; `peek` enables hover previews (the month view only).
FocusScope {
    id: grid
    required property var card
    property int year: card.c.viewYear
    property int month: card.c.viewMonth
    property string selected: ""
    property bool peek: true
    signal picked(string key)
    signal prev()
    signal next()
    signal titleClicked()
    readonly property var cells: Model.monthGrid(year, month, card.c.locale.firstDayOfWeek === 0 ? 7 : card.c.locale.firstDayOfWeek)
    readonly property string monthKey: year + "-" + String(month + 1).padStart(2, "0")
    readonly property var busyDays: card.c.busy[monthKey] || []
    readonly property string todayKey: Model.dayKey(Math.floor(Date.now() / 1000))
    property int focusIndex: -1
    implicitHeight: col.implicitHeight
    Keys.onPressed: event => {
        const step = ({ [Qt.Key_Left]: -1, [Qt.Key_Right]: 1, [Qt.Key_Up]: -7, [Qt.Key_Down]: 7 })[event.key];
        if (step !== undefined) {
            if (focusIndex < 0) focusIndex = Math.max(0, cells.findIndex(c => c.key === (selected || todayKey)));
            // Below the last row ↓ is not the grid's: the card takes it (Upcoming unfolds).
            if (step === 7 && focusIndex >= 35) { event.accepted = false; return; }
            focusIndex = Math.max(0, Math.min(41, focusIndex + step));
            event.accepted = true;
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && focusIndex >= 0) {
            grid.picked(cells[focusIndex].key); event.accepted = true;
        } else if (event.key === Qt.Key_PageUp) { grid.prev(); event.accepted = true; }
        else if (event.key === Qt.Key_PageDown) { grid.next(); event.accepted = true; }
        else event.accepted = false;
    }
    ColumnLayout {
        id: col
        width: parent.width
        spacing: grid.card.px(4)
        RowLayout {
            Layout.fillWidth: true
            Text { text: "‹"; color: grid.card.c.accent; font.pixelSize: grid.card.px(18)
                MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: grid.prev() } }
            Item { Layout.fillWidth: true; implicitHeight: name.implicitHeight
                Text { id: name; objectName: "monthName"; anchors.centerIn: parent
                    text: grid.card.c.locale.standaloneMonthName(grid.month, Locale.LongFormat) + " " + grid.year
                    color: grid.card.c.foreground; font.family: grid.card.c.monoFont; font.pixelSize: grid.card.px(13); font.weight: Font.DemiBold
                    MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: grid.titleClicked() } } }
            Text { text: "›"; color: grid.card.c.accent; font.pixelSize: grid.card.px(18)
                MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: grid.next() } }
        }
        GridLayout {
            columns: 7; columnSpacing: 0; rowSpacing: grid.card.px(3)
            Layout.fillWidth: true
            Repeater {
                model: 7
                delegate: Text {
                    required property int index
                    objectName: "weekday" + index
                    Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                    // Qt numbers days 0 = Sunday … 6 = Saturday, as firstDayOfWeek does.
                    text: grid.card.c.locale.dayName((grid.card.c.locale.firstDayOfWeek + index) % 7, Locale.ShortFormat)
                    color: grid.card.dim; font.family: grid.card.c.monoFont; font.pixelSize: grid.card.px(12)
                }
            }
            Repeater {
                model: grid.cells
                delegate: Rectangle {
                    id: cell
                    required property var modelData
                    required property int index
                    readonly property bool today: modelData.key === grid.todayKey
                    readonly property bool busy: modelData.inMonth && grid.busyDays.indexOf(modelData.day) >= 0
                    Layout.fillWidth: true
                    implicitHeight: grid.card.px(30)
                    radius: grid.card.px(10)
                    color: today ? grid.card.c.accent : (hover.containsMouse ? grid.card.line : "transparent")
                    border.width: modelData.key === grid.selected || index === grid.focusIndex ? 1.5 : 0
                    border.color: grid.card.c.foreground
                    opacity: modelData.inMonth ? 1 : 0.32
                    Text { anchors.horizontalCenter: parent.horizontalCenter; y: grid.card.px(5)
                        text: cell.modelData.day; color: cell.today ? grid.card.c.accentInk : grid.card.c.foreground
                        font.family: grid.card.c.monoFont; font.pixelSize: grid.card.px(13); font.weight: cell.today ? Font.Bold : Font.Normal }
                    Rectangle { objectName: "dot-" + cell.modelData.key.slice(0, 7) + "-" + cell.modelData.day
                        visible: cell.busy; width: grid.card.px(4); height: width; radius: width / 2
                        anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: grid.card.px(2)
                        color: cell.today ? grid.card.c.accentInk : grid.card.c.accent }
                    MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; onClicked: grid.picked(cell.modelData.key) }
                    Timer { running: grid.peek && cell.busy && hover.containsMouse; interval: 300; onTriggered: grid.card.peekDay(cell, cell.modelData.key) }
                    Connections { target: hover; function onContainsMouseChanged() { if (!hover.containsMouse) grid.card.unpeek(cell); } }
                }
            }
        }
    }
    WheelHandler { onWheel: event => { if (event.angleDelta.y > 0) grid.prev(); else if (event.angleDelta.y < 0) grid.next(); } }
}
