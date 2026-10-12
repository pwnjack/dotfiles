import QtQuick
import QtQuick.Controls
import "model.mjs" as Model

// The time pill while editing: accepts 18, 18:30, 18.30, 6pm; Return or
// leaving the field applies it; anything unreadable shakes and puts the old value back.
TextField {
    id: field
    required property var card
    property int value: 0
    signal chosen(int minutes)
    activeFocusOnTab: true
    // The pill's own box (Pill.qml: label + 24, 30 tall, text centred), so the
    // pill turns into a field in place. It keeps that size while you type: a
    // longer entry scrolls inside it rather than moving the row.
    TextMetrics { id: shownWidth; font: field.font; text: field.shown() }
    implicitWidth: shownWidth.advanceWidth + card.px(24)
    clip: true
    implicitHeight: card.px(30)
    padding: 0
    leftPadding: card.px(12)
    rightPadding: card.px(12)
    horizontalAlignment: TextInput.AlignHCenter
    verticalAlignment: TextInput.AlignVCenter
    color: card.c.foreground
    selectionColor: card.c.accent
    selectedTextColor: card.c.accentInk
    font.family: card.c.monoFont
    font.pixelSize: card.px(13)
    background: Rectangle {
        implicitWidth: 0
        implicitHeight: 0
        radius: field.card.px(8)
        color: Qt.rgba(field.card.c.accent.r, field.card.c.accent.g, field.card.c.accent.b, 0.30)
        border.width: 1
        border.color: field.card.c.accent
    }
    transform: Translate { id: shift }
    SequentialAnimation {
        id: shake
        NumberAnimation { target: shift; property: "x"; to: -6; duration: 40 }
        NumberAnimation { target: shift; property: "x"; to: 6; duration: 80 }
        NumberAnimation { target: shift; property: "x"; to: 0; duration: 40 }
    }
    function shown() { return Model.formatTime(value, field.card.c.clock, field.card.c.locale.amText, field.card.c.locale.pmText); }
    onVisibleChanged: if (visible) { text = shown(); forceActiveFocus(); selectAll(); }
    function apply() {
        const m = Model.parseTime(text);
        if (m === null) { text = shown(); shake.restart(); return; }
        field.chosen(m);
    }
    // Applies a typed value. Esc hides the field without calling this, so that value is dropped.
    function commit() { if (visible) apply(); }
    Keys.onReturnPressed: event => { apply(); event.accepted = true; }
    Keys.onEnterPressed: event => { apply(); event.accepted = true; }
    onEditingFinished: commit()
}
