// Edit a playlist's title, description and visibility — TIDAL's own
// "Playlist bearbeiten" dialog, reached from the playlist page header and
// from the sidebar's playlist context menu. The caller owns placement
// (anchors.fill the window) and open/close state; this component only asks
// to close via the signal.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    required property var playlists
    property bool open: false
    signal closeRequested()

    // The opener has no round-trip of its own for this — the sidebar's
    // flattened rows and the playlist page's header already carry these
    // fields, so `load()` just seeds the fields from whichever is at hand.
    property string playlistUuid: ""
    property bool isPublic: false

    function load(uuid, playlistTitle, description, publicFlag) {
        playlistUuid = uuid
        titleField.text = playlistTitle
        descArea.text = description
        isPublic = publicFlag
    }

    visible: root.open
    enabled: root.open

    Keys.onEscapePressed: root.closeRequested()

    onOpenChanged: if (open) titleField.forceActiveFocus()

    function save() {
        if (titleField.text.trim().length === 0)
            return
        root.playlists.update_metadata(root.playlistUuid, titleField.text, descArea.text, root.isPublic)
        root.closeRequested()
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.55

        TapHandler { onSingleTapped: root.closeRequested() }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: 420
        implicitHeight: content.implicitHeight + Theme.spaceLg * 2
        radius: Theme.radiusLg
        color: Theme.elevated
        border.color: Theme.border
        border.width: 1

        // Claims clicks landing on the panel so they don't fall through to
        // the scrim behind it.
        TapHandler {}

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: Theme.spaceLg
            spacing: Theme.space

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Edit playlist"
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

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceXs

                Text {
                    text: "Title"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textFaint
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: Theme.radiusSm
                    color: Theme.inset
                    border.color: titleField.activeFocus ? Theme.accent : Theme.border
                    border.width: 1

                    TextInput {
                        id: titleField
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spaceSm
                        anchors.rightMargin: Theme.spaceSm
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        color: Theme.textPrimary
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.onAccent
                        onAccepted: root.save()
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceXs

                Text {
                    text: "Description"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textFaint
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 96
                    radius: Theme.radiusSm
                    color: Theme.inset
                    border.color: descArea.activeFocus ? Theme.accent : Theme.border
                    border.width: 1
                    clip: true

                    Flickable {
                        id: descFlick
                        anchors.fill: parent
                        anchors.margins: Theme.spaceSm
                        contentWidth: width
                        contentHeight: descArea.implicitHeight
                        clip: true

                        TextEdit {
                            id: descArea
                            width: descFlick.width
                            wrapMode: TextEdit.WordWrap
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: Theme.textPrimary
                            selectionColor: Theme.accent
                            selectedTextColor: Theme.onAccent
                        }
                    }
                }
            }

            SettingRow {
                Layout.fillWidth: true
                label: "Make public"
                description: "Visible on your profile and open to anyone."
                toggleMode: true
                checked: root.isPublic
                onToggled: (value) => root.isPublic = value
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.border
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignRight
                spacing: Theme.spaceSm

                Rectangle {
                    implicitWidth: 84
                    implicitHeight: 34
                    radius: Theme.radiusSm
                    color: cancelHover.hovered ? Theme.hlFaint : "transparent"
                    border.color: Theme.border
                    border.width: 1

                    HoverHandler { id: cancelHover }
                    TapHandler { onSingleTapped: root.closeRequested() }

                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        color: Theme.textSecondary
                    }
                }

                Rectangle {
                    implicitWidth: 84
                    implicitHeight: 34
                    radius: Theme.radiusSm
                    opacity: titleField.text.trim().length > 0 ? 1 : 0.4
                    color: saveHover.hovered ? Theme.accentHover : Theme.accent

                    HoverHandler { id: saveHover; enabled: titleField.text.trim().length > 0 }
                    TapHandler { enabled: titleField.text.trim().length > 0; onSingleTapped: root.save() }

                    Text {
                        anchors.centerIn: parent
                        text: "Save"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.weight: Font.DemiBold
                        color: Theme.onAccent
                    }
                }
            }
        }
    }
}
