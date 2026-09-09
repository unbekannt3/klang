// One playlist: header (cover, title, owner, counts) then its tracks. The
// whole page scrolls together, tidal.com-style, rather than pinning the
// header like FavoritesPage does.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    required property var player
    property var favorites: null

    /// Bubbles a row's right-click up to the window's shared menu.
    signal trackContextRequested(var track, real x, real y)
    property string playlistUuid: ""
    /// Set by the router so the header can render before load_playlist returns.
    property string playlistTitle: ""
    signal openAlbum(int albumId)
    signal openArtist(int artistId)
    signal openPlaylist(string uuid, string title)

    PlaylistsController { id: playlists }

    readonly property var meta: JSON.parse(playlists.playlist_json || "{}")
    readonly property var trackRows: JSON.parse(playlists.tracks_json || "[]")

    function openEditDialog() {
        editDialog.load(root.playlistUuid, root.meta.title || root.playlistTitle,
                         root.meta.description || "", !!root.meta.public)
        editDialog.open = true
    }

    readonly property string metaLine: {
        const parts = []
        if (meta.owner)
            parts.push(meta.owner)
        const count = meta.trackCount || 0
        parts.push(count + (count === 1 ? " track" : " tracks"))
        parts.push(Format.duration(meta.duration))
        return parts.join(" · ")
    }

    // Mirrors TrackList's own header height so it never carries a second
    // scrollbar inside the page's Flickable. Reserve room while the first
    // load is in flight so the spinner isn't squeezed into a sliver.
    readonly property int trackListHeight: playlists.loading && trackRows.length === 0
        ? 240 : 34 + trackRows.length * Theme.rowHeight

    function reload() {
        if (root.playlistUuid.length > 0)
            playlists.load_playlist(root.playlistUuid)
    }

    onPlaylistUuidChanged: reload()
    Component.onCompleted: reload()

    Rectangle {
        anchors.fill: parent
        color: Theme.base
    }

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: content.implicitHeight

        HoverHandler { id: flickHover }

        WheelScroller {
            view: flick
            rowHeight: Theme.rowHeight
        }

        QQC2.ScrollBar.vertical: ThemedScrollBar {
            listHovered: flickHover.hovered
        }

        ColumnLayout {
            id: content
            width: flick.width
            spacing: 0

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: headerRow.implicitHeight + Theme.spaceLg * 2

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.accent }
                        GradientStop { position: 1.0; color: Theme.base }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: Theme.base
                    opacity: 0.55
                }

                RowLayout {
                    id: headerRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.spaceLg
                    spacing: Theme.spaceLg

                    CoverArt {
                        Layout.preferredWidth: 160
                        Layout.preferredHeight: 160
                        Layout.alignment: Qt.AlignBottom
                        uuid: root.meta.image || ""
                        placeholderGlyph: "≡"
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignBottom
                        spacing: Theme.spaceXs

                        Text {
                            text: "PLAYLIST"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm - 1
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1.5
                            color: Theme.textSecondary
                        }

                        Text {
                            text: root.meta.title || root.playlistTitle
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeDisplay
                            font.weight: Font.Bold
                            color: Theme.textPrimary
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: (root.meta.description || "").length > 0
                            text: root.meta.description || ""
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: Theme.textSecondary
                        }

                        Text {
                            text: root.metaLine
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: Theme.textMuted
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spaceLg
                Layout.topMargin: Theme.space
                Layout.bottomMargin: Theme.spaceSm
                spacing: Theme.space

                PlayActions {
                    player: root.player
                    tracks: playlists.tracks_json
                    source: "playlist:" + root.playlistUuid
                }

                Rectangle {
                    implicitWidth: editLabel.implicitWidth + Theme.space
                    implicitHeight: 34
                    radius: Theme.radiusFull
                    color: editHover.hovered ? Theme.hlFaint : Theme.inset
                    border.color: Theme.border
                    border.width: 1

                    HoverHandler { id: editHover }
                    TapHandler { onSingleTapped: root.openEditDialog() }

                    Text {
                        id: editLabel
                        anchors.centerIn: parent
                        text: "Edit"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.weight: Font.DemiBold
                        color: Theme.textPrimary
                    }
                }

                Item { Layout.fillWidth: true }
            }

            Item {
                id: trackListArea
                Layout.fillWidth: true
                Layout.preferredHeight: root.trackListHeight

                TrackList {
                    filterable: true
                    anchors.fill: parent
                    tracks: playlists.tracks_json
                    numbered: true
                    loading: playlists.loading
                    activeId: root.player.track_id
                    favorites: root.favorites
                    onContextRequested: (index, x, y) => {
                        const rows = JSON.parse(playlists.tracks_json || "[]")
                        if (rows[index])
                            root.trackContextRequested(rows[index], x, y)
                    }
                    emptyText: playlists.error.length > 0 ? playlists.error : "This playlist has no tracks"
                    onTrackActivated: (index) =>
                            root.player.play_context(playlists.tracks_json, index, "playlist:" + root.playlistUuid)
                }

                // Drag-to-reorder overlay. TrackList itself is off-limits, so
                // the grips live in the left gutter its rows already leave
                // empty (x < Theme.spaceLg) and the drop index is computed
                // from pointer position against its known header height (34)
                // and Theme.rowHeight, rather than reaching into its delegates.
                Item {
                    id: reorderLayer
                    anchors.fill: parent
                    visible: root.trackRows.length > 1 && !playlists.loading

                    readonly property int headerHeight: 34
                    property int dragFromIndex: -1
                    property int dropIndex: -1

                    function commit() {
                        if (dragFromIndex >= 0 && dropIndex >= 0 && dropIndex !== dragFromIndex)
                            playlists.move_track(root.playlistUuid, dragFromIndex, dropIndex)
                        dragFromIndex = -1
                        dropIndex = -1
                    }

                    Rectangle {
                        visible: reorderLayer.dragFromIndex >= 0
                        x: Theme.spaceLg
                        y: reorderLayer.headerHeight + reorderLayer.dragFromIndex * Theme.rowHeight
                        width: parent.width - Theme.spaceLg * 2
                        height: Theme.rowHeight
                        radius: Theme.radiusXs
                        color: Theme.hlFaint
                    }

                    Rectangle {
                        visible: reorderLayer.dragFromIndex >= 0 && reorderLayer.dropIndex >= 0
                        x: Theme.spaceLg
                        width: parent.width - Theme.spaceLg * 2
                        height: 2
                        radius: 1
                        color: Theme.accent
                        y: reorderLayer.headerHeight + reorderLayer.dropIndex * Theme.rowHeight
                           + (reorderLayer.dropIndex > reorderLayer.dragFromIndex ? Theme.rowHeight : 0)

                        Behavior on y { NumberAnimation { duration: Theme.durationFast } }
                    }

                    Repeater {
                        model: root.trackRows.length

                        delegate: Item {
                            id: handle
                            required property int index

                            x: 0
                            y: reorderLayer.headerHeight + index * Theme.rowHeight
                            width: Theme.spaceLg
                            height: Theme.rowHeight

                            HoverHandler { id: gripHover; cursorShape: Qt.SizeAllCursor }

                            Text {
                                anchors.centerIn: parent
                                text: "⋮⋮"
                                rotation: 90
                                font.pixelSize: 10
                                color: dragHandler.active ? Theme.accent
                                     : gripHover.hovered ? Theme.textSecondary : Theme.textFaint
                            }

                            DragHandler {
                                id: dragHandler
                                target: null
                                onActiveChanged: {
                                    if (active) {
                                        reorderLayer.dragFromIndex = handle.index
                                        reorderLayer.dropIndex = handle.index
                                    } else {
                                        reorderLayer.commit()
                                    }
                                }
                                onCentroidChanged: {
                                    if (!active)
                                        return
                                    const p = handle.mapToItem(reorderLayer, centroid.position.x, centroid.position.y)
                                    let idx = Math.floor((p.y - reorderLayer.headerHeight) / Theme.rowHeight)
                                    reorderLayer.dropIndex = Math.max(0, Math.min(idx, root.trackRows.length - 1))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ScrollMemory {
        flickable: flick
        pageKey: "playlist:" + root.playlistUuid
    }

    PlaylistEditDialog {
        id: editDialog
        anchors.fill: parent
        playlists: playlists
        onCloseRequested: open = false
    }

    StickyHeader {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        flickable: flick
        threshold: 200
        cover: root.meta.image || ""
        title: root.meta.title || root.playlistTitle
        subtitle: root.metaLine

        PlayActions {
            player: root.player
            tracks: playlists.tracks_json
            source: "playlist:" + root.playlistUuid
        }
    }

}
