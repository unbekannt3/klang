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
    required property int userId

    LibraryController { id: library }

    function reload() {
        if (userId !== 0)
            library.load_favorites(userId, 100)
    }

    onUserIdChanged: reload()
    Component.onCompleted: reload()

    Rectangle {
        anchors.fill: parent
        color: Theme.base
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // tidal.com's own collection pages have no coloured banner: a plain
        // title, then Play and Shuffle, then the list.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spaceLg
            Layout.rightMargin: Theme.spaceLg
            Layout.topMargin: Theme.spaceLg
            Layout.bottomMargin: Theme.space
            spacing: Theme.spaceSm

            Text {
                text: "Loved Tracks"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeDisplay
                font.weight: Font.Bold
                color: Theme.textPrimary
            }

            Text {
                visible: library.total > 0
                text: library.total + " tracks"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textMuted
            }

            PlayActions {
                Layout.topMargin: Theme.spaceSm
                player: root.player
                tracks: library.tracks_json
                source: "favorites"
            }
        }

        TrackList {
            scrollKey: "favorites"
            Layout.fillWidth: true
            Layout.fillHeight: true
            tracks: library.tracks_json
            loading: library.loading
            activeId: root.player.track_id
            favorites: root.favorites
            filterable: true
            onContextRequested: (index, x, y) => {
                const rows = JSON.parse(library.tracks_json || "[]")
                if (rows[index])
                    root.trackContextRequested(rows[index], x, y)
            }
            emptyText: library.error.length > 0 ? library.error : "No loved tracks yet"
            onTrackActivated: (index) =>
                root.player.play_context(library.tracks_json, index, "favorites")
        }
    }
}
