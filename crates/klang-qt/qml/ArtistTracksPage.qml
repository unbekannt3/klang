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

    function trackListHeight(count) {
        return 34 + Math.max(count, 1) * Theme.rowHeight
    }

    function playAll() {
        if (root.tracks().length > 0)
            root.player.play_context(viewAll.tracks_json, 0, "artist-tracks:" + root.artistId)
    }

    // The queue already shuffles on `set_context` once shuffle mode is on
    // (see Queue::set_context), so turning it on first is all Shuffle needs.
    function shufflePlay() {
        if (!root.player.shuffle)
            root.player.toggle_shuffle()
        root.playAll()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.base
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        HoverHandler { id: pageHover }

        WheelScroller {
            view: flick
            rowHeight: Theme.rowHeight
        }

        QQC2.ScrollBar.vertical: ThemedScrollBar {
            listHovered: pageHover.hovered
        }

        ColumnLayout {
            id: column
            width: flick.width
            spacing: Theme.space

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spaceLg
                Layout.rightMargin: Theme.spaceLg
                Layout.topMargin: Theme.spaceLg
                spacing: Theme.spaceXs

                Text {
                    text: "Popular tracks"
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

                Rectangle {
                    implicitWidth: playRow.implicitWidth + Theme.spaceLg
                    implicitHeight: 44
                    radius: Theme.radiusFull
                    color: playHover.hovered ? Theme.accentHover : Theme.accent

                    HoverHandler { id: playHover }
                    TapHandler { onSingleTapped: root.playAll() }

                    RowLayout {
                        id: playRow
                        anchors.centerIn: parent
                        spacing: Theme.spaceXs

                        Icon {
                            width: 16
                            height: 16
                            name: "play"
                            color: Theme.onAccent
                        }

                        Text {
                            text: "Play"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.weight: Font.Bold
                            color: Theme.onAccent
                        }
                    }
                }

                Rectangle {
                    implicitWidth: shuffleRow.implicitWidth + Theme.spaceLg
                    implicitHeight: 44
                    radius: Theme.radiusFull
                    color: shuffleHover.hovered ? Theme.buttonHover : Theme.button

                    HoverHandler { id: shuffleHover }
                    TapHandler { onSingleTapped: root.shufflePlay() }

                    RowLayout {
                        id: shuffleRow
                        anchors.centerIn: parent
                        spacing: Theme.spaceXs

                        Icon {
                            width: 16
                            height: 16
                            name: "shuffle"
                            color: Theme.textPrimary
                        }

                        Text {
                            text: "Shuffle"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.weight: Font.Bold
                            color: Theme.textPrimary
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }

            TrackList {
                Layout.fillWidth: true
                Layout.preferredHeight: root.trackListHeight(root.tracks().length)
                tracks: viewAll.tracks_json
                loading: viewAll.loading
                activeId: root.player.track_id
                favorites: root.favorites
                onContextRequested: (index, x, y) => {
                    const rows = root.tracks()
                    if (rows[index])
                        root.trackContextRequested(rows[index], x, y)
                }
                emptyText: viewAll.error.length > 0 ? viewAll.error : "No tracks"
                onTrackActivated: (index) =>
                        root.player.play_context(viewAll.tracks_json, index, "artist-tracks:" + root.artistId)
            }

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
                    text: "Show more"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    font.weight: Font.DemiBold
                    color: Theme.textPrimary
                }
            }
        }
    }

    ScrollMemory {
        flickable: flick
        pageKey: "artist-tracks:" + root.artistId
    }
}
