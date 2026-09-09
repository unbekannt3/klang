// Vertical stack of CardCarousels, shared by Home and Explore. The page owns
// the controller; this just renders {title, kind, items} sections and routes
// activation by item kind.

import QtQuick
import QtQuick.Controls as QQC2
import me.unbk.klang

Item {
    id: root

    required property var player
    /// JSON string or array of {title, kind, items}.
    property var sections: []
    property bool loading: false
    property string error: ""
    property string emptyText: Tr.t("Nothing here")
    property var favorites: null
    /// Scroll position is remembered per key across navigation.
    property string scrollKey: ""

    signal openAlbum(int albumId)
    signal openArtist(int artistId)
    signal openPlaylist(string uuid, string title)
    signal openMix(string mixId, string title)
    /// Right-click on a card, in this list's coordinates.
    signal itemContextRequested(var item, real x, real y)
    /// A section header opened in full.
    signal openSection(var section)

    function rows() {
        if (typeof sections === "string")
            return JSON.parse(sections || "[]")
        return sections || []
    }

    function activate(item) {
        MediaRoute.open(item, {
            album: root.openAlbum,
            artist: root.openArtist,
            playlist: root.openPlaylist,
            mix: root.openMix,
            play: (it) => root.player.play(parseInt(it.id), it.title, it.subtitle, 0, it.image),
        })
    }

    ListView {
        id: view
        anchors.fill: parent
        clip: true
        model: root.rows()
        spacing: Theme.spaceXl
        topMargin: Theme.spaceLg
        bottomMargin: Theme.spaceLg
        reuseItems: true

        HoverHandler { id: listHover }

        WheelScroller {
            view: view
            rowHeight: Theme.cardSize
        }

        QQC2.ScrollBar.vertical: ThemedScrollBar {
            listHovered: listHover.hovered
        }

        delegate: CardCarousel {
            required property var modelData
            favorites: root.favorites
            width: view.width
            title: modelData.title || ""
            items: modelData.items || []
            hasViewAll: !!modelData.apiPath
            onItemActivated: (item) => root.activate(item)
            onItemPlayRequested: (item) => root.activate(item)
            onItemContextRequested: (item, x, y) => {
                const p = mapToItem(root, x, y)
                root.itemContextRequested(item, p.x, p.y)
            }
            onViewAllRequested: root.openSection(modelData)
        }
    }

    Text {
        anchors.centerIn: parent
        visible: view.count === 0 && !root.loading
        text: root.error.length > 0 ? root.error : root.emptyText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeLg
        color: Theme.textFaint
    }

    ScrollMemory {
        flickable: view
        pageKey: root.scrollKey
    }

    QQC2.BusyIndicator {
        anchors.centerIn: parent
        running: root.loading && Theme.animated
    }
}
