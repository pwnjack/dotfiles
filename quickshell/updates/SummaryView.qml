pragma ComponentBehavior: Bound
import QtQuick
import "model.mjs" as Model

// ① What is pending. Package names stay behind the disclosure, which is
// collapsed every time the card opens (shell.qml resets `expanded`).
Column {
    id: view
    required property var card
    required property var controller
    readonly property var info: Model.summary(controller.plan, controller.planError)
    readonly property bool canUpdate: info.canUpdate
    readonly property int rowHeight: card.px(24)
    spacing: card.px(14)

    function focusPrimary() {
        (view.info.canUpdate ? update : later).forceActiveFocus();
    }
    // The plan arrives after the card opens: Update takes focus when it
    // appears, behind the same key guard as a newly shown view.
    onCanUpdateChanged: if (canUpdate && card.mode === "summary") { card.armKeys(); focusPrimary(); }

    Header {
        width: parent.width
        card: view.card
        busy: view.info.busy
        title: view.info.title
        subtitle: view.info.subtitle
    }

    Column {
        width: parent.width
        visible: view.info.repo > 0
        Item {
            width: parent.width
            height: view.card.px(32)
            Rectangle {
                anchors.fill: parent
                radius: view.card.px(10)
                color: disclosure.containsMouse ? Qt.rgba(view.card.foreground.r, view.card.foreground.g, view.card.foreground.b, 0.07) : "transparent"
            }
            Row {
                anchors.left: parent.left
                anchors.leftMargin: view.card.px(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: view.card.px(8)
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String.fromCodePoint(0xf0142)
                    color: view.card.dim
                    font.family: view.card.monoFont
                    font.pixelSize: view.card.px(13)
                    rotation: view.controller.expanded ? 90 : 0
                    Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (view.controller.expanded ? "Hide" : "Show") + " packages"
                    color: view.card.foreground
                    font.family: view.card.monoFont
                    font.pixelSize: view.card.px(12.5)
                }
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: view.card.px(10)
                anchors.verticalCenter: parent.verticalCenter
                text: view.info.repo
                color: view.card.dim
                font.family: view.card.monoFont
                font.pixelSize: view.card.px(12.5)
                font.features: ({ "tnum": 1 })
            }
            MouseArea {
                id: disclosure
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: view.controller.toggleList()
            }
        }
        Item {
            id: listClip
            objectName: "listClip"
            width: parent.width
            clip: true
            height: view.controller.expanded ? Math.min(list.count * view.rowHeight + 2, view.card.px(214)) : 0
            Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            Rectangle { width: parent.width; height: 1; color: view.card.hairline }
            ListView {
                id: list
                anchors.fill: parent
                anchors.topMargin: 1
                anchors.bottomMargin: 1
                model: view.controller.plan ? view.controller.plan.repo : []
                boundsBehavior: Flickable.StopAtBounds
                delegate: Item {
                    id: row
                    required property var modelData
                    width: ListView.view.width
                    height: view.rowHeight
                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: view.card.px(10)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: view.card.px(8)
                        Text {
                            id: name
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, row.width - view.card.px(32) - version.width
                                - (tag.visible ? tag.width + view.card.px(8) : 0))
                            text: row.modelData.name
                            elide: Text.ElideRight
                            color: view.card.foreground
                            font.family: view.card.monoFont
                            font.pixelSize: view.card.px(12)
                        }
                        // The mockup's tag on a package that replaces the running kernel.
                        Rectangle {
                            id: tag
                            visible: row.modelData.kernel === true
                            anchors.verticalCenter: parent.verticalCenter
                            width: tagText.implicitWidth + view.card.px(8)
                            height: tagText.implicitHeight
                            radius: view.card.px(5)
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(view.card.accent.r, view.card.accent.g, view.card.accent.b, 0.5)
                            Text {
                                id: tagText
                                anchors.centerIn: parent
                                text: "restart"
                                color: view.card.accent
                                font.family: view.card.monoFont
                                font.pixelSize: view.card.px(10)
                                font.letterSpacing: 0.6
                            }
                        }
                    }
                    Text {
                        id: version
                        anchors.right: parent.right
                        anchors.rightMargin: view.card.px(10)
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.StyledText
                        text: Model.versionMarkup(row.modelData.old, row.modelData.new, String(view.card.accent))
                        color: view.card.dim
                        font.family: view.card.monoFont
                        font.pixelSize: view.card.px(12)
                        font.features: ({ "tnum": 1 })
                    }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: view.card.hairline }
        }
    }

    Item {
        visible: view.info.terminal !== ""
        width: parent.width
        height: terminalLink.implicitHeight
        Text {
            anchors.left: parent.left
            anchors.leftMargin: view.card.px(10)
            anchors.right: terminalLink.left
            anchors.rightMargin: view.card.px(10)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: view.info.note
            color: view.card.dim
            font.family: view.card.monoFont
            font.pixelSize: view.card.px(12.5)
        }
        Text {
            id: terminalLink
            objectName: "terminalLink"
            anchors.right: parent.right
            anchors.rightMargin: view.card.px(10)
            anchors.verticalCenter: parent.verticalCenter
            text: "Update in terminal"
            color: view.card.accent
            font.family: view.card.monoFont
            font.pixelSize: view.card.px(12.5)
            font.underline: true
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: view.controller.terminal(view.info.terminal)
            }
        }
    }

    Row {
        anchors.right: parent.right
        spacing: view.card.px(8)
        CardButton {
            id: later
            card: view.card
            text: view.info.canUpdate ? "Later" : "Close"
            hint: "Esc"
            onClicked: view.controller.close()
        }
        CardButton {
            id: update
            card: view.card
            visible: view.info.canUpdate
            kind: "primary"
            text: "Update"
            hint: "↵"
            onClicked: view.controller.start()
        }
    }
}
