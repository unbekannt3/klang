// Catalogue search: tracks, albums, artists and playlists, grouped like
// tidal.com's results page.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    required property var player
    /// Seeded by the router; the in-page field takes over from here.
    property string query: ""
    signal openAlbum(int albumId)
    signal openArtist(int artistId)
    signal openPlaylist(string uuid, string title)

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
        subtitle: p.numberOfTracks + " tracks",
        image: p.image,
        kind: "playlist"
    }))

    readonly property bool hasResults: trackRows.length > 0 || albumCards.length > 0
                                        || artistCards.length > 0 || playlistCards.length > 0

    readonly property string emptyMessage: search.error.length > 0 ? search.error
        : (search.query.length > 0 && !hasResults ? "No results for “" + search.query + "”" : "")

    // Mirrors TrackList's own header height so it never carries a second
    // scrollbar inside the page's Flickable.
    readonly property int trackListHeight: 34 + trackRows.length * Theme.rowHeight

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

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: results.implicitHeight

            HoverHandler { id: flickHover }

            WheelScroller {
                view: flick
                rowHeight: Theme.rowHeight
            }

            QQC2.ScrollBar.vertical: ThemedScrollBar {
                listHovered: flickHover.hovered
            }

            ColumnLayout {
                id: results
                width: flick.width
                spacing: Theme.spaceLg

                Item { Layout.preferredHeight: Theme.spaceSm }

                TrackList {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.trackListHeight
                    visible: root.trackRows.length > 0
                    tracks: search.tracks_json
                    activeId: root.player.track_id
                    onTrackActivated: (id, title, artist, duration, cover) =>
                        root.player.play(id, title, artist, duration, cover)
                }

                CardCarousel {
                    Layout.fillWidth: true
                    visible: root.albumCards.length > 0
                    title: "Albums"
                    items: root.albumCards
                    onItemActivated: (item) => root.openAlbum(item.id)
                }

                CardCarousel {
                    Layout.fillWidth: true
                    visible: root.artistCards.length > 0
                    title: "Artists"
                    items: root.artistCards
                    onItemActivated: (item) => root.openArtist(item.id)
                }

                CardCarousel {
                    Layout.fillWidth: true
                    visible: root.playlistCards.length > 0
                    title: "Playlists"
                    items: root.playlistCards
                    onItemActivated: (item) => root.openPlaylist(item.id, item.title)
                }

                Item { Layout.preferredHeight: Theme.spaceLg }
            }
        }
    }

    QQC2.BusyIndicator {
        anchors.centerIn: parent
        running: search.loading
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
