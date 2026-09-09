// Discord Rich Presence. This page only has the settings bridge, not the
// player, so the preview substitutes sample track data rather than the
// track actually playing.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

ColumnLayout {
    id: root

    required property var settings

    spacing: Theme.space

    readonly property var tags: ["{track}", "{artist}", "{album}"]
    property string draftStatusText: ""

    readonly property string previewText: {
        let rendered = (root.draftStatusText || "")
            .split("{track}").join("High Hopes")
            .split("{artist}").join("Pink Floyd")
            .split("{album}").join("The Division Bell")
            .trim()
        return rendered.length > 0 ? rendered : "TIDAL via klang"
    }

    function syncFromSettings() { root.draftStatusText = root.settings.discord_status_text }

    Component.onCompleted: root.syncFromSettings()
    Connections {
        target: root.settings
        function onDiscord_status_textChanged() { root.syncFromSettings() }
    }

    component StatusField: Rectangle {
        id: field
        property alias text: input.text
        property string placeholder: ""
        signal committed()

        implicitHeight: 32
        radius: Theme.radiusXs
        color: Theme.inset
        border.color: input.activeFocus ? Theme.accent : Theme.border
        border.width: 1

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: Theme.spaceSm
            anchors.rightMargin: Theme.spaceSm
            verticalAlignment: TextInput.AlignVCenter
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textPrimary
            selectionColor: Theme.accent
            selectedTextColor: Theme.onAccent
            onAccepted: field.committed()

            Text {
                visible: input.text.length === 0
                text: field.placeholder
                font: input.font
                color: Theme.textFaint
            }
        }
    }

    SettingRow {
        Layout.fillWidth: true
        label: Tr.t("Discord Rich Presence")
        description: Tr.t("Shows what you're listening to on Discord.")
        toggleMode: true
        checked: root.settings.discord_rpc
        onToggled: (value) => root.settings.apply_discord_rpc(value)
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.space
        spacing: Theme.space
        visible: root.settings.discord_rpc

        SettingRow {
            Layout.fillWidth: true
            label: Tr.t("Status text")
            description: Tr.t("Tags are replaced with the currently playing track.")

            StatusField {
                implicitWidth: 260
                placeholder: "{track} by {artist} on {album}"
                text: root.draftStatusText
                onTextChanged: root.draftStatusText = text
                onCommitted: root.settings.apply_discord_status_text(root.draftStatusText)
            }
        }

        Row {
            Layout.fillWidth: true
            spacing: Theme.spaceSm

            Repeater {
                model: root.tags

                Rectangle {
                    id: tagPill
                    required property string modelData

                    implicitWidth: tagText.implicitWidth + Theme.space
                    implicitHeight: 26
                    radius: Theme.radiusSm
                    color: hover.hovered ? Theme.hlFaint : "transparent"
                    border.color: Theme.accent
                    border.width: 1

                    HoverHandler { id: hover }
                    TapHandler {
                        onSingleTapped: {
                            root.draftStatusText += tagPill.modelData
                            root.settings.apply_discord_status_text(root.draftStatusText)
                        }
                    }

                    Text {
                        id: tagText
                        anchors.centerIn: parent
                        text: tagPill.modelData
                        font.family: Theme.fontFamilyMono
                        font.pixelSize: Theme.fontSizeSm
                        color: Theme.accent
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: previewCol.implicitHeight + Theme.space
            radius: Theme.radius
            color: Theme.inset
            border.color: Theme.border
            border.width: 1

            ColumnLayout {
                id: previewCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Theme.spaceSm
                spacing: 2

                Text {
                    text: "Preview"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    font.weight: Font.DemiBold
                    color: Theme.textFaint
                }
                Text {
                    Layout.fillWidth: true
                    text: "Listening to " + root.previewText
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: Theme.textSecondary
                }
            }
        }
    }
}
