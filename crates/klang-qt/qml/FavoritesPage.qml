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

        // Header band. The gradient stands in for the cover-derived colour the
        // real client pulls from artwork.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 180

            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.accent }
                GradientStop { position: 1.0; color: Theme.base }
            }

            // Knock the gradient back so the title stays readable on any accent.
            Rectangle {
                anchors.fill: parent
                color: Theme.base
                opacity: 0.55
            }

            ColumnLayout {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: Theme.spaceLg
                spacing: Theme.spaceXs

                Text {
                    text: "COLLECTION"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm - 1
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.5
                    color: Theme.textSecondary
                }

                Text {
                    text: "Loved Tracks"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeDisplay
                    font.weight: Font.Bold
                    color: Theme.textPrimary
                }

                Text {
                    text: library.total > 0 ? library.total + " tracks" : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textMuted
                }
            }
        }

        TrackList {
            Layout.fillWidth: true
            Layout.fillHeight: true
            tracks: library.tracks_json
            loading: library.loading
            activeId: root.player.track_id
            favorites: root.favorites
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
