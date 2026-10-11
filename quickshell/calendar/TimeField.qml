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
    implicitWidth: card.px(90)
    color: card.c.foreground
    font.family: card.c.monoFont
    font.pixelSize: card.px(13)
    background: Rectangle {
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
