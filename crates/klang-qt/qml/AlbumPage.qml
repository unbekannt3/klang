// Album detail: header band, then the album's tracks.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    required property var player
    /// Album to display.
    property int albumId: 0
    /// Navigation requests bubble up to Main.qml.
    signal openAlbum(int albumId)
    signal openArtist(int artistId)
    signal openPlaylist(string uuid, string title)

    readonly property int coverSize: 220

    CatalogController { id: catalog }

    function album() {
        return JSON.parse(catalog.album_json || "{}")
    }

    function reload() {
        if (albumId !== 0)
            catalog.load_album(albumId)
    }

    onAlbumIdChanged: reload()
    Component.onCompleted: reload()

    function year(iso) {
        return iso ? iso.substring(0, 4) : ""
    }

    // TIDAL dates are plain "YYYY-MM-DD"; parsing that through Date() and
    // reading it back with local getters can shift the day across a UTC
    // offset, so split it by hand instead.
    function formatDate(iso) {
        const months = ["January", "February", "March", "April", "May", "June",
                         "July", "August", "September", "October", "November", "December"]
        const p = (iso || "").split("-")
        const month = p.length >= 3 ? months[parseInt(p[1], 10) - 1] : undefined
        return month ? parseInt(p[2], 10) + " " + month + " " + p[0] : iso
    }

    // TIDAL prints both dates when a reissue's stream date differs from the
    // original release — the reason album_json carries both (see catalog.rs).
    function releaseLine() {
        const a = root.album()
        if (!a.releaseDate)
            return ""
        let text = root.formatDate(a.releaseDate)
        if (a.originalReleaseDate && a.originalReleaseDate !== a.releaseDate)
            text += " (" + root.formatDate(a.originalReleaseDate) + ")"
        const count = a.trackCount || 0
        text += " · " + count + (count === 1 ? " track" : " tracks")
        text += " (" + Format.duration(a.duration) + ")"
        if (a.copyright)
            text += " · " + a.copyright
        return text
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
                Layout.preferredHeight: root.coverSize + Theme.spaceLg * 2

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
                        uuid: root.album().cover || ""
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spaceXs

                        Text {
                            text: "ALBUM"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm - 1
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1.5
                            color: Theme.textSecondary
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.album().title || ""
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeDisplay
                            font.weight: Font.Bold
                            color: Theme.textPrimary
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.album().artist || ""
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeLg
                            color: artistHover.hovered ? Theme.textPrimary : Theme.textSecondary

                            HoverHandler { id: artistHover }
                            TapHandler { onSingleTapped: root.openArtist(root.album().artistId || 0) }
                        }

                        Text {
                            text: [root.year(root.album().releaseDate),
                                   (root.album().trackCount || 0) + " tracks",
                                   Format.duration(root.album().duration)].join(" · ")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: Theme.textMuted
                        }
                    }
                }
            }

            TrackList {
                Layout.fillWidth: true
                Layout.preferredHeight: root.trackListHeight(root.album().trackCount || 0)
                tracks: catalog.album_tracks_json
                loading: catalog.loading
                activeId: root.player.track_id
                numbered: true
                showCovers: false
                showBpm: false
                showKey: false
                emptyText: catalog.error.length > 0 ? catalog.error : "No tracks"
                onTrackActivated: (id, title, artist, duration, cover) =>
                    root.player.play(id, title, artist, duration, cover)
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spaceLg
                Layout.rightMargin: Theme.spaceLg
                Layout.bottomMargin: Theme.spaceLg
                visible: text.length > 0
                text: root.releaseLine()
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textFaint
            }
        }
    }
}
