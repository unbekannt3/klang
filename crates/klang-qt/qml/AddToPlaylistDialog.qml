// Centred modal for adding one track to a playlist, or creating a new one
// on the fly. The caller owns placement (anchors.fill the window) and the
// open/close state; this component only asks to close via the signal.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    required property var playlists
    property int trackId: 0
    property bool open: false
    signal closeRequested()

    visible: root.open
    enabled: root.open

    Keys.onEscapePressed: root.closeRequested()

    function playlistRows() {
        const all = JSON.parse(root.playlists.playlists_json || "[]")
        return all.filter((r) => r.kind === "playlist")
    }

    readonly property var rows: root.playlistRows()
    readonly property var filteredRows: filterField.text.length === 0
        ? root.rows
        : root.rows.filter((r) => r.title.toLowerCase().includes(filterField.text.toLowerCase()))

    property bool creating: false

    // Also on completion: a caller that builds this on demand hands it `open`
    // as an initial value, which is no property change to react to.
    function reset() {
        if (!root.open)
            return
        filterField.text = ""
        root.creating = false
        newTitleField.text = ""
        filterField.forceActiveFocus()
    }

    onOpenChanged: root.reset()
    Component.onCompleted: root.reset()

    function addTo(uuid) {
        root.playlists.add_track(uuid, root.trackId)
        root.closeRequested()
    }

    function createAndAdd() {
        if (newTitleField.text.length === 0)
            return
        root.playlists.create_with_track(newTitleField.text, root.trackId)
        root.closeRequested()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.overlay
        opacity: 0.55

        TapHandler {
            onSingleTapped: root.closeRequested()
        }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: 420
        height: 480
        radius: Theme.radiusLg
        color: Theme.elevated
        border.color: Theme.border
        border.width: 1

        // Claims clicks landing on the panel so they don't fall through to
        // the scrim behind it.
        TapHandler {}

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spaceLg
            spacing: Theme.spaceSm

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Add to playlist")
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

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                radius: Theme.radiusFull
                color: Theme.inset
                border.color: filterField.activeFocus ? Theme.accent : "transparent"
                border.width: 1

                Icon {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spaceSm
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14
                    height: 14
                    name: "search"
                    color: Theme.textFaint
                }

                TextInput {
                    id: filterField
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space + Theme.spaceSm
                    anchors.rightMargin: Theme.spaceSm
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textPrimary
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.onAccent

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: !filterField.text
                        text: Tr.t("Find a playlist")
                        font: filterField.font
                        color: Theme.textFaint
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceXs

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: Theme.radiusSm
                    color: newRowHover.hovered ? Theme.hlFaint : "transparent"

                    HoverHandler { id: newRowHover }
                    TapHandler {
                        onSingleTapped: {
                            root.creating = !root.creating
                            if (root.creating)
                                newTitleField.forceActiveFocus()
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spaceSm
                        anchors.rightMargin: Theme.spaceSm
                        spacing: Theme.space

                        Rectangle {
                            implicitWidth: 32
                            implicitHeight: 32
                            radius: 16
                            color: Theme.inset

                            Icon {
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                name: "playlist"
                                color: Theme.textPrimary
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: Tr.t("New playlist")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            color: Theme.textPrimary
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.creating
                    spacing: Theme.spaceSm

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: Theme.radiusSm
                        color: Theme.inset
                        border.color: newTitleField.activeFocus ? Theme.accent : Theme.border
                        border.width: 1

                        TextInput {
                            id: newTitleField
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
                            onAccepted: root.createAndAdd()

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: !newTitleField.text
                                text: Tr.t("Playlist name")
                                font: newTitleField.font
                                color: Theme.textFaint
                            }
                        }
                    }

                    Rectangle {
                        implicitWidth: 68
                        implicitHeight: 34
                        radius: Theme.radiusSm
                        opacity: newTitleField.text.length > 0 ? 1 : 0.4
                        color: createHover.hovered ? Theme.accentHover : Theme.accent

                        HoverHandler { id: createHover; enabled: newTitleField.text.length > 0 }
                        TapHandler {
                            enabled: newTitleField.text.length > 0
                            onSingleTapped: root.createAndAdd()
                        }

                        Text {
                            anchors.centerIn: parent
                            text: Tr.t("Create")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Font.DemiBold
                            color: Theme.onAccent
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.border
            }

            // Plain Item, not a Layout child of the list itself, so the empty
            // label can overlay the ListView instead of fighting it for space.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: list
                    anchors.fill: parent
                    clip: true
                    model: root.filteredRows
                    reuseItems: true

                    HoverHandler { id: listHover }
                    WheelScroller { view: list; rowHeight: Theme.rowHeight }
                    QQC2.ScrollBar.vertical: ThemedScrollBar { listHovered: listHover.hovered }

                    delegate: Rectangle {
                        id: row
                        required property var modelData

                        width: list.width
                        height: Theme.rowHeight
                        radius: Theme.radiusXs
                        color: rowHover.hovered ? Theme.hlFaint : "transparent"

                        HoverHandler { id: rowHover }
                        TapHandler { onSingleTapped: root.addTo(row.modelData.id) }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spaceSm
                            anchors.rightMargin: Theme.spaceSm
                            spacing: Theme.space

                            CoverArt {
                                Layout.preferredWidth: Theme.coverThumb
                                Layout.preferredHeight: Theme.coverThumb
                                uuid: row.modelData.image || ""
                                placeholderGlyph: "≡"
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.title
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    color: Theme.textPrimary
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: Tr.t(row.modelData.trackCount === 1
                                               ? "%1 track" : "%1 tracks")
                                            .arg(row.modelData.trackCount)
                                    elide: Text.ElideRight
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    color: Theme.textMuted
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: filterField.text.length > 0 ? "No playlists found" : "No playlists yet"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: Theme.textFaint
                }
            }
        }
    }
}
