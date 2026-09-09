// One mix: header (cover, title, track count) then its tracks.
//
// The page takes its data as plain properties rather than owning a
// MixController, so the caller decides which mix is loaded and how — track
// radio, for one, has only a track id until the controller resolves it.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    required property var player
    property string mixId: ""
    property string mixTitle: ""
    /// Album cover uuid for the header. TIDAL sends one for its own mixes;
    /// track radio has none until the mix loads, so the caller seeds it with
    /// the track's cover.
    property string mixImage: ""
    /// JSON string or array of track rows (see klang-qt's rows.rs).
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

                CoverArt {
                    Layout.preferredWidth: root.coverSize
                    Layout.preferredHeight: root.coverSize
                    Layout.alignment: Qt.AlignBottom
                    uuid: root.mixImage
                    placeholderGlyph: "♪"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    spacing: Theme.spaceXs

                    Text {
                        text: Tr.t("MIX")
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
                        text: root.trackRows.length > 0
                              ? Tr.t("%1 tracks").arg(root.trackRows.length) : ""
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
            tracks: root.mixItems
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
            emptyText: root.error.length > 0 ? Tr.t(root.error)
                                             : Tr.t("This mix has no tracks")
            onTrackActivated: (index) =>
                root.player.play_context(root.mixItems, index, "mix:" + root.mixId)
            onArtistActivated: (id) => root.openArtist(id)
            onAlbumActivated: (id) => root.openAlbum(id)
        }
    }
}
