import QtQuick

// Badge + title + subtitle. `check` draws the done state's check mark in.
Row {
    id: header
    required property var card
    property int glyph: 0xf06b0
    property bool check: false
    property bool busy: false
    property color tint: card.accent
    // The mockup's badge fill: 22% normally, 26% for done, 18% for amber.
    property real badgeAlpha: 0.22
    property string title
    property string subtitle
    spacing: card.px(12)

    Rectangle {
        id: badge
        width: header.card.px(40)
        height: width
        radius: header.card.px(12)
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.rgba(header.tint.r, header.tint.g, header.tint.b, header.badgeAlpha)
        Text {
            anchors.centerIn: parent
            visible: !header.check
            opacity: header.busy ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 200 } }
            text: String.fromCodePoint(header.glyph)
            color: header.tint
            font.family: header.card.monoFont
            font.pixelSize: header.card.px(20)
        }
        Canvas {
            id: spinner
            objectName: "spinner"
            anchors.fill: parent
            opacity: header.busy && !header.check ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            RotationAnimator on rotation {
                from: 0
                to: 360
                duration: 1000
                easing.type: Easing.Linear
                loops: Animation.Infinite
                // Spins through the fade-out instead of freezing mid-turn.
                running: spinner.opacity > 0 && header.visible
            }
            Connections {
                target: header
                function onTintChanged() { spinner.requestPaint(); }
            }
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const s = header.card.px(20) / 20;
                ctx.strokeStyle = header.tint;
                ctx.lineWidth = 2 * s;
                ctx.lineCap = "round";
                ctx.beginPath();
                ctx.arc(width / 2, height / 2, 7.5 * s, 0, 3 * Math.PI / 2);
                ctx.stroke();
            }
        }
        Canvas {
            id: mark
            anchors.fill: parent
            visible: header.check
            property real drawn: 0
            onDrawnChanged: requestPaint()
            onVisibleChanged: if (visible) { drawn = 0; draw.restart(); }
            SequentialAnimation {
                id: draw
                PauseAnimation { duration: 100 }
                NumberAnimation { target: mark; property: "drawn"; from: 0; to: 1; duration: 450; easing.type: Easing.OutCubic }
            }
            // The mockup's check: (4.5,10.5) -> (8,14) -> (15.5,6) in a 20-unit
            // box, centred in the badge at the badge glyph's size.
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const s = header.card.px(20) / 20;
                const o = (width - 20 * s) / 2;
                const first = Math.hypot(3.5, 3.5), second = Math.hypot(7.5, 8);
                let left = drawn * (first + second);
                ctx.strokeStyle = header.tint;
                ctx.lineWidth = 2 * s;
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                ctx.beginPath();
                ctx.moveTo(o + 4.5 * s, o + 10.5 * s);
                const a = Math.min(1, left / first);
                ctx.lineTo(o + (4.5 + 3.5 * a) * s, o + (10.5 + 3.5 * a) * s);
                left -= first;
                if (left > 0) {
                    const b = Math.min(1, left / second);
                    ctx.lineTo(o + (8 + 7.5 * b) * s, o + (14 - 8 * b) * s);
                }
                ctx.stroke();
            }
        }
    }
    Column {
        anchors.verticalCenter: parent.verticalCenter
        width: header.width - badge.width - header.spacing
        spacing: header.card.px(2)
        Text {
            objectName: "title"
            width: parent.width
            text: header.title
            color: header.card.foreground
            font.family: header.card.monoFont
            font.pixelSize: header.card.px(15)
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
        }
        Text {
            width: parent.width
            text: header.subtitle
            color: header.card.dim
            font.family: header.card.monoFont
            font.pixelSize: header.card.px(12.5)
            lineHeight: 1.15
            wrapMode: Text.Wrap
        }
    }
}
