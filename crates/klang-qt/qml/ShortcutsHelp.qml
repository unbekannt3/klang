// Read-only cheat sheet for Shortcuts.qml's fixed bindings. Klang has no
// rebinding UI, so this only documents what is live rather than editing it.
import QtQuick
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    property bool open: false
    signal closeRequested()

    visible: root.open
    enabled: root.open

    Keys.onEscapePressed: root.closeRequested()

    // Kept in the same order as Shortcuts.qml. Zoom and app-data refresh are
    // not implemented (see the task report), so they are not listed here.
    readonly property var rows: [
        { key: "Space", label: Tr.t("Play / Pause") },
        { key: "Ctrl+→", label: Tr.t("Next track") },
        { key: "Ctrl+←", label: Tr.t("Previous track") },
        { key: "Ctrl+↑", label: Tr.t("Volume up") },
        { key: "Ctrl+↓", label: Tr.t("Volume down") },
        { key: "M", label: Tr.t("Mute / Unmute") },
        { key: "L", label: Tr.t("Like / Unlike current track") },
        { key: "Alt+S", label: Tr.t("Shuffle on / off") },
        { key: "Alt+R", label: Tr.t("Repeat off / all / one") },
        { key: "Ctrl+K", label: Tr.t("Focus search bar") },
        { key: "Esc", label: Tr.t("Dismiss overlay") },
        { key: "Ctrl+E", label: Tr.t("Toggle exclusive output") },
        { key: "Ctrl+B", label: Tr.t("Toggle bit-perfect mode") },
        { key: "Shift+?", label: Tr.t("Show this help") },
    ]
    readonly property int splitAt: Math.ceil(rows.length / 2)

    component ShortcutRow: RowLayout {
        id: row
        required property string label
        required property string keyLabel
        spacing: Theme.spaceSm

        Rectangle {
            implicitWidth: keyText.implicitWidth + Theme.space
            implicitHeight: 22
            radius: Theme.radiusXs
            color: Theme.inset
            border.color: Theme.border
            border.width: 1

            Text {
                id: keyText
                anchors.centerIn: parent
                text: row.keyLabel
                font.family: Theme.fontFamilyMono
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textSecondary
            }
        }

        Text {
            Layout.fillWidth: true
            text: row.label
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textPrimary
        }
    }

    ModalShield {
        blocksPage: true
        scrim: Qt.alpha(Theme.overlay, 0.55)
        onDismissed: root.closeRequested()
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: 560
        height: content.implicitHeight + Theme.spaceLg * 2
        radius: Theme.radiusLg
        color: Theme.elevated
        border.color: Theme.border
        border.width: 1

        // Claims clicks landing on the panel so they don't fall through to
        // the scrim behind it.
        // Keeps clicks on the panel from also reaching the scrim.
        ModalShield {}

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spaceLg
            spacing: Theme.space

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Keyboard shortcuts")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeLg
                    font.weight: Font.DemiBold
                    color: Theme.textPrimary
                }

                Item {
                    implicitWidth: 24
                    implicitHeight: 24

                    HoverHandler { id: closeHover }
                    TapHandler { onSingleTapped: root.closeRequested() }

                    Icon {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        name: "close"
                        color: closeHover.hovered ? Theme.textPrimary : Theme.textFaint
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceLg

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spaceSm

                    Repeater {
                        model: root.rows.slice(0, root.splitAt)
                        delegate: ShortcutRow {
                            required property var modelData
                            label: modelData.label
                            keyLabel: modelData.key
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spaceSm

                    Repeater {
                        model: root.rows.slice(root.splitAt)
                        delegate: ShortcutRow {
                            required property var modelData
                            label: modelData.label
                            keyLabel: modelData.key
                        }
                    }
                }
            }
        }
    }
}
