// An artist's full track list ("Popular tracks" opened in full), with Play
// and Shuffle above it — the one sub-page that's a track list rather than a
// grid, so it doesn't share ViewAllPage.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    required property var player
    property var favorites: null
    property int artistId: 0
    property string artistName: ""

    /// Bubbles a row's right-click up to the window's shared menu.
    signal trackContextRequested(var track, real x, real y)
    signal openArtist(int artistId)
    signal openAlbum(int albumId)

    ViewAllController { id: viewAll }

    function reload() {
        if (root.artistId > 0)
            viewAll.load_artist_tracks(root.artistId)
    }

    onArtistIdChanged: reload()
    Component.onCompleted: reload()

    function tracks() {
        return JSON.parse(viewAll.tracks_json || "[]")
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


            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spaceLg
                Layout.rightMargin: Theme.spaceLg
                Layout.topMargin: Theme.spaceLg
                spacing: Theme.spaceXs

                Text {
                    text: Tr.t("Popular tracks")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeDisplay
                    font.weight: Font.Bold
                    color: Theme.textPrimary
                }

                Text {
                    visible: root.artistName.length > 0
                    text: root.artistName
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: Theme.textMuted
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spaceLg
                Layout.rightMargin: Theme.spaceLg
                spacing: Theme.space

                PlayActions {
                    player: root.player
                    tracks: viewAll.tracks_json
                    source: "artist-tracks:" + root.artistId
                }

                Item { Layout.fillWidth: true }
            }

        }
    }

    Component {
        id: pageFooterContent

        ColumnLayout {
            width: parent ? parent.width : 0
            spacing: Theme.spaceLg


            Rectangle {
                visible: viewAll.has_more
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: Theme.spaceLg
                opacity: viewAll.loading ? 0.5 : 1
                implicitWidth: moreLabel.implicitWidth + Theme.spaceLg
                implicitHeight: 38
                radius: Theme.radiusFull
                color: moreHover.hovered ? Theme.hlFaint : Theme.inset
                border.color: Theme.border
                border.width: 1

                HoverHandler { id: moreHover }
                TapHandler {
                    enabled: !viewAll.loading
                    onSingleTapped: viewAll.load_more_tracks()
                }

                Text {
                    id: moreLabel
                    anchors.centerIn: parent
                    text: Tr.t("Show more")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    font.weight: Font.DemiBold
                    color: Theme.textPrimary
                }
            }
        }
    }

    TrackList {
        id: trackList
        anchors.fill: parent
        scrollKey: "artist-tracks:" + root.artistId
        pageHeader: pageHeaderContent
        pageFooter: pageFooterContent
            Layout.fillWidth: true
            tracks: viewAll.tracks_json
            loading: viewAll.loading
            activeId: root.player.track_id
            favorites: root.favorites
            onContextRequested: (index, x, y) => {
                const rows = root.tracks()
                if (rows[index])
                    root.trackContextRequested(rows[index], x, y)
            }
            emptyText: viewAll.error.length > 0 ? viewAll.error : Tr.t("No tracks")
            onTrackActivated: (index) =>
                    root.player.play_context(viewAll.tracks_json, index, "artist-tracks:" + root.artistId)
            onArtistActivated: (id) => root.openArtist(id)
            onAlbumActivated: (id) => root.openAlbum(id)
    }


}
