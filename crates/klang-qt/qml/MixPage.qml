// One mix: header (cover, title, track count) then its tracks.
//
// No bridge exposes `get_mix_items` (klang-core/api/pages.rs) yet, so this
// page takes its data as plain properties instead of owning a controller —
// see the caller contract on `mixItems` below.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    required property var player
    property string mixId: ""
    property string mixTitle: ""
    /// JSON string or array of track rows (see klang-qt's rows.rs), supplied
    /// by the caller until a MixController with get_mix_items exists.
    property var mixItems: []
    property bool loading: false
    property string error: ""

    property var favorites: null
    /// Bubbles a row's right-click up to the window's shared menu.
    signal trackContextRequested(var track, real x, real y)
    signal openAlbum(int albumId)
    signal openArtist(int artistId)

    readonly property var trackRows: typeof mixItems === "string"
        ? JSON.parse(mixItems || "[]") : (mixItems || [])
    readonly property int coverSize: 132

    Rectangle {
        anchors.fill: parent
        color: Theme.base
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 180

            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.accent }
                GradientStop { position: 1.0; color: Theme.base }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.base
                opacity: 0.55
            }

            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Theme.spaceLg
                spacing: Theme.space

                // No bridge yet carries the mix's own header image (TIDAL's
                // MixPageResult.image), so this shows the placeholder glyph.
                CoverArt {
                    Layout.preferredWidth: root.coverSize
                    Layout.preferredHeight: root.coverSize
                    Layout.alignment: Qt.AlignBottom
                    placeholderGlyph: "♪"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    spacing: Theme.spaceXs

                    Text {
                        text: "MIX"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm - 1
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.5
                        color: Theme.textSecondary
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.mixTitle
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeDisplay
                        font.weight: Font.Bold
                        color: Theme.textPrimary
                    }

                    Text {
                        text: root.trackRows.length > 0 ? root.trackRows.length + " tracks" : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        color: Theme.textMuted
                    }
                }
            }
        }

        PlayActions {
            Layout.leftMargin: Theme.spaceLg
            Layout.topMargin: Theme.space
            Layout.bottomMargin: Theme.spaceSm
            player: root.player
            tracks: JSON.stringify(root.trackRows)
            source: "mix:" + root.mixId
        }

        TrackList {
            scrollKey: "mix:" + root.mixId
            Layout.fillWidth: true
            Layout.fillHeight: true
            tracks: root.mixItems
            loading: root.loading
            activeId: root.player.track_id
            favorites: root.favorites
            onContextRequested: (index, x, y) => {
                if (root.trackRows[index])
                    root.trackContextRequested(root.trackRows[index], x, y)
            }
            emptyText: root.error.length > 0 ? root.error : "This mix has no tracks"
            onTrackActivated: (index) =>
                root.player.play_context(JSON.stringify(root.trackRows), index, "mix:" + root.mixId)
        }
    }
}
