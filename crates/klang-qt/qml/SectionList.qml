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
    property string emptyText: "Nothing here"

    signal openAlbum(int albumId)
    signal openArtist(int artistId)
    signal openPlaylist(string uuid, string title)

    function rows() {
        if (typeof sections === "string")
            return JSON.parse(sections || "[]")
        return sections || []
    }

    // TIDAL's own home feed defaults unrecognised item shapes to "track" too
    // (see item_kind in home.rs), so treat anything else the same way here.
    function activate(item) {
        switch (item.kind) {
        case "album":
            root.openAlbum(parseInt(item.id))
            break
        case "artist":
            root.openArtist(parseInt(item.id))
            break
        case "playlist":
        case "mix":
            root.openPlaylist(item.id, item.title)
            break
        default:
            root.player.play(parseInt(item.id), item.title, item.subtitle, 0, item.image)
        }
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
            width: view.width
            title: modelData.title || ""
            items: modelData.items || []
            onItemActivated: (item) => root.activate(item)
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

    QQC2.BusyIndicator {
        anchors.centerIn: parent
        running: root.loading
    }
}
