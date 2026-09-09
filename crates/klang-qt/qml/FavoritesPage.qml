// Loved tracks.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    required property var player
    property var favorites: null

    /// Bubbles a row's right-click up to the window's shared menu.
    signal trackContextRequested(var track, real x, real y)
    signal openArtist(int artistId)
    signal openAlbum(int albumId)
    required property int userId

    LibraryController { id: library }

    function reload() {
        if (userId !== 0)
            library.load_favorites(userId, 100)
    }

    // Playback starts from the page that is loaded; the rest is pulled in
    // behind it and appended to the queue as it lands, so a collection plays
    // past its first hundred without waiting for one.
    function fillQueue() {
        library.load_all_favorites()
        root.player.extend_context(library.tracks_json, "favorites")
    }

    Connections {
        target: library
        function onTracks_jsonChanged() {
            if (root.player.source === "favorites")
                root.player.extend_context(library.tracks_json, "favorites")
        }
    }

    Timer {
        id: reloadDebounce
        interval: 0
        onTriggered: root.reload()
    }

    onUserIdChanged: reloadDebounce.restart()
    Component.onCompleted: reloadDebounce.restart()

    Rectangle {
        anchors.fill: parent
        color: Theme.base
    }

    // tidal.com's own collection pages have no coloured banner: a plain
    // title, then Play and Shuffle, then the list.
    Component {
        id: header

        ColumnLayout {
            width: parent ? parent.width : 0
            spacing: Theme.spaceSm

            Text {
                Layout.leftMargin: Theme.spaceLg
                Layout.topMargin: Theme.spaceLg
                text: Tr.t("Loved Tracks")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeDisplay
                font.weight: Font.Bold
                color: Theme.textPrimary
            }

            Text {
                Layout.leftMargin: Theme.spaceLg
                visible: library.total > 0
                text: library.total + " " + Tr.t("tracks")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textMuted
            }

            PlayActions {
                Layout.leftMargin: Theme.spaceLg
                Layout.topMargin: Theme.spaceSm
                Layout.bottomMargin: Theme.space
                player: root.player
                tracks: library.tracks_json
                source: "favorites"
                onPlayed: root.fillQueue()
            }
        }
    }

    TrackList {
        anchors.fill: parent
        scrollKey: "favorites"
        pageHeader: header
        tracks: library.tracks_json
        loading: library.loading
        activeId: root.player.track_id
        favorites: root.favorites
        filterable: true
        // TIDAL's own sort keys, which is what the column names are.
        sortColumn: library.sort_order
        sortDescending: library.sort_direction === "DESC"
        onSortRequested: (column) => {
            const flip = column === library.sort_order && library.sort_direction === "DESC"
            library.set_sort(column, flip ? "ASC" : "DESC")
        }
        emptyText: library.error.length > 0 ? library.error : Tr.t("Nothing here")
        onEndReached: library.load_more_favorites()
        onContextRequested: (index, x, y) => {
            const rows = JSON.parse(library.tracks_json || "[]")
            if (rows[index])
                root.trackContextRequested(rows[index], x, y)
        }
        onTrackActivated: (index) => {
            root.player.play_context(library.tracks_json, index, "favorites")
            root.fillQueue()
        }
        onArtistActivated: (id) => root.openArtist(id)
        onAlbumActivated: (id) => root.openAlbum(id)
    }
}
