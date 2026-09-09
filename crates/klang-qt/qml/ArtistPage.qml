// Artist detail: header band, popular tracks, then their albums.

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
    /// Artist to display.
    property int artistId: 0
    /// Navigation requests bubble up to Main.qml.
    signal openAlbum(int albumId)
    signal openArtist(int artistId)
    signal openPlaylist(string uuid, string title)
    /// "Popular tracks" opened in full.
    signal openArtistTracks(string artistName)
    /// A carousel opened as a grid of the cards it already holds.
    signal openItemGrid(string title, var items)
    signal itemContextRequested(var item, real x, real y)

    readonly property int avatarSize: 200
    property bool bioExpanded: false

    CatalogController { id: catalog }

    function artist() {
        return JSON.parse(catalog.artist_json || "{}")
    }

    function topTracks() {
        return JSON.parse(catalog.artist_top_tracks_json || "[]")
    }

    function albumCards() {
        const albums = JSON.parse(catalog.artist_albums_json || "[]")
        return albums.map(a => ({
            id: a.id,
            title: a.title,
            subtitle: root.year(a.releaseDate),
            image: a.cover || "",
            kind: "album"
        }))
    }

    function reload() {
        if (artistId !== 0)
            catalog.load_artist(artistId)
    }

    onArtistIdChanged: reload()
    Component.onCompleted: reload()

    function year(iso) {
        return iso ? iso.substring(0, 4) : ""
    }


    Rectangle {
        anchors.fill: parent
        color: Theme.base
    }

    Component {
        id: pageHeaderContent

        ColumnLayout {
            width: parent ? parent.width : 0
            spacing: Theme.spaceLg


            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.avatarSize + Theme.spaceLg * 2

                RowLayout {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.spaceLg
                    spacing: Theme.space

                    CoverArt {
                        Layout.preferredWidth: root.avatarSize
                        Layout.preferredHeight: root.avatarSize
                        radius: width / 2
                        placeholderGlyph: "☺"
                        uuid: root.artist().picture || ""
                    }

                    ColumnLayout {
                        spacing: Theme.spaceXs

                        Text {
                            text: "ARTIST"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm - 1
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1.5
                            color: Theme.textSecondary
                        }

                        Text {
                            text: root.artist().name || ""
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeDisplay
                            font.weight: Font.Bold
                            color: Theme.textPrimary
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spaceLg
                Layout.rightMargin: Theme.spaceLg
                visible: bioText.text.length > 0
                spacing: Theme.spaceXs

                Text {
                    id: bioText
                    Layout.fillWidth: true
                    text: root.artist().bio || ""
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                    maximumLineCount: root.bioExpanded ? 1000 : 4
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textSecondary
                }

                Text {
                    visible: bioText.truncated || root.bioExpanded
                    text: root.bioExpanded ? "Show less" : "Show more"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    font.weight: Font.DemiBold
                    color: toggleHover.hovered ? Theme.textPrimary : Theme.accent

                    HoverHandler { id: toggleHover }
                    TapHandler { onSingleTapped: root.bioExpanded = !root.bioExpanded }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spaceLg
                Layout.rightMargin: Theme.spaceLg

                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Popular tracks")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeHeading
                    font.weight: Font.Bold
                    color: Theme.textPrimary
                }

                Text {
                    text: Tr.t("View all")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    font.weight: Font.DemiBold
                    color: allTracksHover.hovered ? Theme.textPrimary : Theme.textMuted

                    HoverHandler { id: allTracksHover }
                    TapHandler { onSingleTapped: root.openArtistTracks(root.artist().name || "") }
                }
            }

        }
    }

    Component {
        id: pageFooterContent

        ColumnLayout {
            width: parent ? parent.width : 0
            spacing: Theme.spaceLg


            CardCarousel {
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.spaceLg
                title: Tr.t("Albums")
                items: root.albumCards()
                hasViewAll: root.albumCards().length > 0
                onItemActivated: (item) => root.openAlbum(item.id)
                onItemPlayRequested: (item) => root.openAlbum(item.id)
                onItemContextRequested: (item, x, y) => {
                    const p = mapToItem(root, x, y)
                    root.itemContextRequested(item, p.x, p.y)
                }
                onViewAllRequested: root.openItemGrid("Albums", root.albumCards())
            }
        }
    }

    TrackList {
        id: trackList
        anchors.fill: parent
        scrollKey: "artist:" + root.artistId
        pageHeader: pageHeaderContent
        pageFooter: pageFooterContent
            Layout.fillWidth: true
            tracks: catalog.artist_top_tracks_json
            loading: catalog.loading
            activeId: root.player.track_id
            favorites: root.favorites
            onContextRequested: (index, x, y) => {
                const rows = JSON.parse(catalog.artist_top_tracks_json || "[]")
                if (rows[index])
                    root.trackContextRequested(rows[index], x, y)
            }
            emptyText: catalog.error.length > 0 ? catalog.error : Tr.t("No tracks")
            onTrackActivated: (index) =>
                    root.player.play_context(catalog.artist_top_tracks_json, index, "artist:" + root.artistId)
    }


    StickyHeader {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        flickable: trackList.scroller
        threshold: root.avatarSize
        cover: root.artist().picture || ""
        title: root.artist().name || ""

        PlayActions {
            player: root.player
            tracks: catalog.artist_top_tracks_json
            source: "artist:" + root.artistId
        }
    }

}
