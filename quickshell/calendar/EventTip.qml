import QtQuick
import QtQuick.Layouts
import "model.mjs" as Model

// The hover popup for one or more events: title, time, calendar · location.
Rectangle {
    id: tip
    required property var card
    property var events: []
    property string heading: ""
    visible: events.length > 0
    width: Math.min(card.px(240), col.implicitWidth + card.px(20))
    height: col.implicitHeight + card.px(16)
    radius: card.px(10)
    z: 10
    color: Qt.rgba(card.c.background.r * 1.6, card.c.background.g * 1.6, card.c.background.b * 1.6, 0.98)
    border.width: 1; border.color: Qt.rgba(card.c.foreground.r, card.c.foreground.g, card.c.foreground.b, 0.2)
    function span(e) {
        if (e.allDay) return "all day";
        const f = m => Model.formatTime(m, card.c.clock, card.c.locale.amText, card.c.locale.pmText);
        return f(Model.minutesOf(e.startEpoch)) + "–" + f(Model.minutesOf(e.endEpoch));
    }
    ColumnLayout {
        id: col
        x: card.px(10); y: card.px(8)
        spacing: card.px(2)
        Text { visible: tip.heading !== ""; text: tip.heading; color: tip.card.dim; font.family: tip.card.c.monoFont; font.pixelSize: tip.card.px(12) }
        Repeater {
            model: tip.events
            delegate: ColumnLayout {
                required property var modelData
                spacing: 0
                RowLayout {
                    spacing: tip.card.px(6)
                    Rectangle { width: tip.card.px(8); height: width; radius: width / 2; color: modelData.color || tip.card.c.accent }
                    Text { text: modelData.title; color: tip.card.c.foreground; font.family: tip.card.c.monoFont
                        font.pixelSize: tip.card.px(12.5); font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.maximumWidth: tip.card.px(200) }
                }
                Text { text: tip.span(modelData); color: tip.card.c.accent; font.family: tip.card.c.monoFont; font.pixelSize: tip.card.px(12.5) }
                Text { visible: text !== ""; text: [modelData.calendar, modelData.location].filter(s => s).join(" · ")
                    color: tip.card.dim; font.family: tip.card.c.monoFont; font.pixelSize: tip.card.px(12); elide: Text.ElideRight
                    Layout.maximumWidth: tip.card.px(220) }
            }
        }
    }
}
