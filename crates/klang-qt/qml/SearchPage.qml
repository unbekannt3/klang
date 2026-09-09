// Catalogue search: tracks, albums, artists, playlists and videos, grouped
// like tidal.com's results page.

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
    /// Seeded by the router; the in-page field takes over from here.
    property string query: ""
    signal openAlbum(int albumId)
    signal openArtist(int artistId)
    signal openPlaylist(string uuid, string title)
    signal openVideo(int videoId)

    readonly property int searchLimit: 25

    SearchController { id: search }

    readonly property var trackRows: JSON.parse(search.tracks_json || "[]")

    readonly property var albumCards: JSON.parse(search.albums_json || "[]").map(a => ({
        id: a.id,
        title: a.title,
        subtitle: a.year ? a.artist + " · " + a.year : a.artist,
        image: a.cover,
        kind: "album"
    }))

    readonly property var artistCards: JSON.parse(search.artists_json || "[]").map(a => ({
        id: a.id,
        title: a.name,
        subtitle: "",
        image: a.picture,
        kind: "artist"
    }))

    readonly property var playlistCards: JSON.parse(search.playlists_json || "[]").map(p => ({
        id: p.uuid,
        title: p.title,
        subtitle: Tr.t("%1 tracks").arg(p.numberOfTracks),
        image: p.image,
        kind: "playlist"
    }))

    // Already card-shaped (see search.rs's video_row) — videos have no page of
    // their own, they open the video player straight from here.
    readonly property var videoCards: JSON.parse(search.videos_json || "[]")

    readonly property bool hasResults: trackRows.length > 0 || albumCards.length > 0
                                        || artistCards.length > 0 || playlistCards.length > 0
                                        || videoCards.length > 0

    readonly property string emptyMessage: search.error.length > 0 ? search.error
        : (search.query.length > 0 && !hasResults ? "No results for “" + search.query + "”" : "")

    // Mirrors TrackList's own header height so it never carries a second
    // scrollbar inside the page's Flickable.

    function reload() {
        if (root.query.length > 0)
            search.search(root.query, root.searchLimit)
        else
            search.clear()
    }

    onQueryChanged: reload()
    Component.onCompleted: reload()


    Rectangle {
        anchors.fill: parent
        color: Theme.base
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

    Component {
        id: pageHeaderContent

        ColumnLayout {
            width: parent ? parent.width : 0
            spacing: Theme.spaceLg

            Item { Layout.preferredHeight: Theme.spaceSm }
        }
    }

    Component {
        id: pageFooterContent

        ColumnLayout {
            width: parent ? parent.width : 0
            spacing: Theme.spaceLg


                CardCarousel {
                    Layout.fillWidth: true
                    visible: root.albumCards.length > 0
                    title: Tr.t("Albums")
                    items: root.albumCards
                    onItemActivated: (item) => root.openAlbum(item.id)
                }

                CardCarousel {
                    Layout.fillWidth: true
                    visible: root.artistCards.length > 0
                    title: Tr.t("Artists")
                    items: root.artistCards
                    onItemActivated: (item) => root.openArtist(item.id)
                }

                CardCarousel {
                    Layout.fillWidth: true
                    visible: root.playlistCards.length > 0
                    title: Tr.t("Playlists")
                    items: root.playlistCards
                    onItemActivated: (item) => root.openPlaylist(item.id, item.title)
                }

                CardCarousel {
                    Layout.fillWidth: true
                    visible: root.videoCards.length > 0
                    title: Tr.t("Videos")
                    items: root.videoCards
                    onItemActivated: (item) => root.openVideo(parseInt(item.id))
                    onItemPlayRequested: (item) => root.openVideo(parseInt(item.id))
                }

                Item { Layout.preferredHeight: Theme.spaceLg }
        }
    }

    TrackList {
        id: trackList
        anchors.fill: parent
        scrollKey: "search:" + root.query
        pageHeader: pageHeaderContent
        pageFooter: pageFooterContent
                Layout.fillWidth: true
                visible: root.trackRows.length > 0
                tracks: search.tracks_json
                activeId: root.player.track_id
                favorites: root.favorites
                onContextRequested: (index, x, y) => {
                    const rows = JSON.parse(search.tracks_json || "[]")
                    if (rows[index])
                        root.trackContextRequested(rows[index], x, y)
                }
                onTrackActivated: (index) =>
                    root.player.play_context(search.tracks_json, index, "search")
    }

    }

    QQC2.BusyIndicator {
        anchors.centerIn: parent
        running: search.loading && Theme.animated
    }

    Text {
        anchors.centerIn: parent
        visible: !search.loading && root.emptyMessage.length > 0
        text: root.emptyMessage
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeLg
        color: Theme.textFaint
    }
}
