import QtQuick

Item {
    id: card
    required property string imageUrl
    required property string title
    required property bool selected
    required property bool reducedMotion
    required property real pixelScale
    required property color accent
    property bool ready: preview.status === Image.Ready
    readonly property real skew: 0.13
    signal clicked

    Rectangle {
        id: frame
        anchors.centerIn: parent
        width: parent.width - 48
        height: parent.height * (card.selected ? 0.96 : 0.82)
        color: "#171b20"
        clip: true
        antialiasing: true
        transform: Matrix4x4 {
            matrix: Qt.matrix4x4(1, -card.skew, 0, frame.height * card.skew / 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
        }
        Behavior on height {
            NumberAnimation {
                duration: card.reducedMotion ? 0 : 240
                easing.type: Easing.OutCubic
            }
        }
        Image {
            id: preview
            anchors.centerIn: parent
            width: frame.width + frame.height * card.skew
            height: frame.height
            // Cancel the frame's shear for the pixels, keeping its skewed clip.
            // Extra width covers both slanted edges throughout the height animation.
            transform: Matrix4x4 {
                matrix: Qt.matrix4x4(1, card.skew, 0, -frame.height * card.skew / 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
            }
            source: card.imageUrl
            asynchronous: true
            cache: false
            // Fixed decode bounds, independent of selection animation. Qt handles
            // cropping without stretching; virtualized delegates bound live images.
            sourceSize: Qt.size(Math.min(1280, Math.ceil((card.width + card.height * card.skew) * card.pixelScale)), Math.min(1440, Math.ceil(card.height * card.pixelScale)))
            fillMode: Image.PreserveAspectCrop
            autoTransform: true
        }
        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: card.selected ? 0 : hover.containsMouse ? 0.12 : 0.34
            Behavior on opacity {
                NumberAnimation {
                    duration: card.reducedMotion ? 0 : 180
                }
            }
        }
        Text {
            anchors.centerIn: parent
            width: parent.width - 48
            text: preview.status === Image.Error ? "Preview unavailable\nChoose another image" : "Loading preview…"
            visible: preview.status !== Image.Ready
            color: "#ffffff"
            font.family: "sans-serif"
            font.pixelSize: 16
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: card.selected ? 3 : 1
            border.color: card.selected ? card.accent : "#50ffffff"
        }
        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.clicked()
        }
        Accessible.role: Accessible.ListItem
        Accessible.name: card.title
        Accessible.selected: card.selected
        Accessible.onPressAction: if (enabled) card.clicked()
    }
}
