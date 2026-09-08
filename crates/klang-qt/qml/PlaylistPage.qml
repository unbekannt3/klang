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
    property string playlistUuid: ""
    /// Set by the router so the header can render before load_playlist returns.
    property string playlistTitle: ""
    signal openAlbum(int albumId)
    signal openArtist(int artistId)
    signal openPlaylist(string uuid, string title)

    PlaylistsController { id: playlists }

    readonly property var meta: JSON.parse(playlists.playlist_json || "{}")
    readonly property var trackRows: JSON.parse(playlists.tracks_json || "[]")

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

            TrackList {
                Layout.fillWidth: true
                Layout.preferredHeight: root.trackListHeight
                tracks: playlists.tracks_json
                numbered: true
                loading: playlists.loading
                activeId: root.player.track_id
                favorites: root.favorites
                emptyText: playlists.error.length > 0 ? playlists.error : "This playlist has no tracks"
                onTrackActivated: (index) =>
                        root.player.play_context(playlists.tracks_json, index, "playlist:" + root.playlistUuid)
            }
        }
    }
}
