// Artist detail: header band, popular tracks, then their albums.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    required property var player
    property var favorites: null
    /// Artist to display.
    property int artistId: 0
    /// Navigation requests bubble up to Main.qml.
    signal openAlbum(int albumId)
    signal openArtist(int artistId)
    signal openPlaylist(string uuid, string title)

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

    function trackListHeight(count) {
        return 34 + Math.max(count, 1) * Theme.rowHeight
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
            spacing: Theme.spaceLg

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.avatarSize + Theme.spaceLg * 2

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

            Text {
                Layout.leftMargin: Theme.spaceLg
                text: "Popular tracks"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeHeading
                font.weight: Font.Bold
                color: Theme.textPrimary
            }

            TrackList {
                Layout.fillWidth: true
                Layout.preferredHeight: root.trackListHeight(root.topTracks().length)
                tracks: catalog.artist_top_tracks_json
                loading: catalog.loading
                activeId: root.player.track_id
                favorites: root.favorites
                emptyText: catalog.error.length > 0 ? catalog.error : "No tracks"
                onTrackActivated: (index) =>
                        root.player.play_context(catalog.artist_top_tracks_json, index, "artist:" + root.artistId)
            }

            CardCarousel {
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.spaceLg
                title: "Albums"
                items: root.albumCards()
                onItemActivated: (item) => root.openAlbum(item.id)
            }
        }
    }
}
