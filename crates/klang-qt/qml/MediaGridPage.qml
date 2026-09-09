// Reusable grid of MediaCards, shared by every "favourite X" page — albums,
// artists, playlists and videos differ only in which controller feeds `items`.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    required property var player
    property string title: ""
    /// JSON string or array of {id, title, subtitle, image, kind}.
    property var items: []
    property bool loading: false
    property string error: ""
    /// FavoritesController; without one the cards' hearts stay hidden.
    property var favorites: null
    /// Scroll position is remembered per key across navigation.
    property string scrollKey: ""
    /// Shown instead of the bare "Nothing here" when the grid is empty, with
    /// the button below it — tidal.com tells you how to fill a collection.
    property string emptyHint: ""
    property string emptyAction: ""
    signal emptyActionRequested()

    signal openAlbum(int albumId)
    signal openArtist(int artistId)
    signal openPlaylist(string uuid, string title)
    signal openMix(string mixId, string title)
    signal openVideo(int videoId)
    /// Right-click on a card, in this page's coordinates.
    signal itemContextRequested(var item, real x, real y)

    function rows() {
        if (typeof items === "string")
            return JSON.parse(items || "[]")
        return items || []
    }

    /// A carousel or grid holds one kind, so the card geometry follows the
    /// first row: video artwork is 16:9 and its card wider than the rest.
    readonly property bool wideCards: {
        const rows = root.rows()
        return rows.length > 0 && rows[0].kind === "video"
    }
    readonly property int cardWidth: root.wideCards ? Theme.videoCardSize : Theme.cardSize
    readonly property int coverHeight: root.wideCards
        ? Math.round(root.cardWidth * 9 / 16) : root.cardWidth

    function activate(item) {
        MediaRoute.open(item, {
            album: root.openAlbum,
            artist: root.openArtist,
            playlist: root.openPlaylist,
            mix: root.openMix,
            video: root.openVideo,
            play: (it) => root.player.play(parseInt(it.id), it.title, it.subtitle, 0, it.image),
        })
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.base
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spaceLg
            Layout.rightMargin: Theme.spaceLg
            Layout.topMargin: Theme.spaceLg
            Layout.bottomMargin: Theme.space
            visible: root.title.length > 0
            text: root.title
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeDisplay
            font.weight: Font.Bold
            color: Theme.textPrimary
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            GridView {
                id: grid
                anchors.fill: parent
                anchors.leftMargin: Theme.spaceLg
                anchors.rightMargin: Theme.spaceLg
                bottomMargin: Theme.contentBottomInset
                clip: true
                model: root.rows()
                reuseItems: true

                // At least one column; more once the width fits another card
                // plus its gutter. Cells then stretch to fill each row evenly.
                readonly property int columns: Math.max(1,
                    Math.floor(width / (root.cardWidth + Theme.spaceLg)))
                cellWidth: width / columns
                cellHeight: root.coverHeight + 52 + Theme.spaceLg

                HoverHandler { id: gridHover }

                WheelScroller {
                    view: grid
                    rowHeight: grid.cellHeight
                }

                QQC2.ScrollBar.vertical: ThemedScrollBar {
                    listHovered: gridHover.hovered
                }

                delegate: Item {
                    id: cell
                    required property var modelData
                    width: grid.cellWidth
                    height: grid.cellHeight

                    MediaCard {
                        anchors.fill: parent

                        // Mixes have no favourite endpoint (see showFavorite below).
                        readonly property bool inLibrary: {
                            if (!root.favorites || !cell.modelData)
                                return false
                            const _revision = root.favorites.revision
                            switch (cell.modelData.kind) {
                            case "album":    return root.favorites.is_album(Number(cell.modelData.id))
                            case "artist":   return root.favorites.is_artist(Number(cell.modelData.id))
                            case "playlist": return root.favorites.is_playlist(String(cell.modelData.id))
                            default:         return false
                            }
                        }

                        function toggleFavorite() {
                            switch (cell.modelData.kind) {
                            case "album":    root.favorites.toggle_album(Number(cell.modelData.id)); break
                            case "artist":   root.favorites.toggle_artist(Number(cell.modelData.id)); break
                            case "playlist": root.favorites.toggle_playlist(String(cell.modelData.id)); break
                            }
                        }

                        anchors.rightMargin: Theme.spaceLg
                        anchors.bottomMargin: Theme.spaceLg
                        title: cell.modelData.title || ""
                        subtitle: cell.modelData.subtitle || ""
                        image: cell.modelData.image || ""
                        kind: cell.modelData.kind || "album"
                        cornerBadge: cell.modelData.kind === "video"
                        mixType: cell.modelData.mixType || ""
                                     ? Format.minutes(cell.modelData.duration) : ""
                        favorited: inLibrary
                        // Mixes and videos have no favourite endpoint in
                        // FavoritesController, so their hearts would do nothing.
                        showFavorite: !!root.favorites
                                      && ["album", "artist", "playlist"].indexOf(cell.modelData.kind) >= 0
                        onFavoriteToggled: toggleFavorite()
                        onActivated: root.activate(cell.modelData)
                        onPlayRequested: root.activate(cell.modelData)
                        onContextRequested: (x, y) => {
                            const p = mapToItem(root, x, y)
                            root.itemContextRequested(cell.modelData, p.x, p.y)
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                visible: grid.count === 0 && !root.loading
                       && root.error.length === 0 && root.emptyHint.length > 0
                spacing: Theme.space

                Icon {
                    Layout.alignment: Qt.AlignHCenter
                    width: 48
                    height: 48
                    name: "play"
                    color: Theme.textFaint
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: 380
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: root.emptyHint
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: Theme.textMuted
                }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.emptyAction.length > 0
                    implicitWidth: emptyActionText.implicitWidth + Theme.spaceXl
                    implicitHeight: 36
                    radius: Theme.radiusFull
                    color: emptyHover.hovered ? Theme.buttonHover : Theme.button

                    Text {
                        id: emptyActionText
                        anchors.centerIn: parent
                        text: root.emptyAction
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        color: Theme.textPrimary
                    }

                    HoverHandler { id: emptyHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onSingleTapped: root.emptyActionRequested() }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: grid.count === 0 && !root.loading
                       && (root.error.length > 0 || root.emptyHint.length === 0)
                text: root.error.length > 0 ? root.error : Tr.t("Nothing here")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLg
                color: Theme.textFaint
            }

            ScrollMemory {
                flickable: grid
                pageKey: root.scrollKey
            }

            QQC2.BusyIndicator {
                anchors.centerIn: parent
                running: root.loading && Theme.animated
            }
        }
    }
}
