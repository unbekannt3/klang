// A titled horizontal strip of MediaCards, the shape TIDAL's home page is
// built from.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

ColumnLayout {
    id: root

    property string title: ""
    /// Array of {id, title, subtitle, image, kind}.
    property var items: []

    signal itemActivated(var item)
    signal itemPlayRequested(var item)
    /// Right-click on a card, in the carousel's coordinates.
    signal itemContextRequested(var item, real x, real y)
    /// Header click, where the section has a dedicated page.
    signal viewAllRequested()

    /// Shows a "View all" affordance next to the title.
    property bool hasViewAll: false
    /// FavoritesController; without one the cards' hearts stay hidden.
    property var favorites: null

    spacing: Theme.spaceSm

    component Arrow: Rectangle {
        id: arrow
        property string iconName: ""
        property bool active: true
        signal activated()

        implicitWidth: 28
        implicitHeight: 28
        radius: width / 2
        opacity: arrow.active ? 1 : 0.25
        color: hover.hovered && arrow.active ? Theme.hlMed : "transparent"

        HoverHandler { id: hover; enabled: arrow.active }
        TapHandler { enabled: arrow.active; onSingleTapped: arrow.activated() }

        Icon {
            anchors.centerIn: parent
            width: 16
            height: 16
            name: arrow.iconName
            color: Theme.textSecondary
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.spaceLg
        Layout.rightMargin: Theme.spaceLg

        Text {
            id: heading
            Layout.fillWidth: true
            text: root.title
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeHeading
            font.weight: Font.Bold
            color: root.hasViewAll && headingHover.hovered ? Theme.accent : Theme.textPrimary

            HoverHandler { id: headingHover; enabled: root.hasViewAll }
            TapHandler { enabled: root.hasViewAll; onSingleTapped: root.viewAllRequested() }
        }

        Text {
            visible: root.hasViewAll
            text: Tr.t("View all")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            font.weight: Font.DemiBold
            color: viewAllHover.hovered ? Theme.textPrimary : Theme.textMuted

            HoverHandler { id: viewAllHover }
            TapHandler { onSingleTapped: root.viewAllRequested() }
        }

        Arrow {
            iconName: "back"
            active: strip.contentX > 0
            onActivated: strip.page(-1)
        }

        Arrow {
            iconName: "forward"
            active: strip.contentX < strip.contentWidth - strip.width - 1
            onActivated: strip.page(1)
        }
    }

    ListView {
        id: strip

        /// Move by a whole screenful of cards.
        function page(direction) {
            const step = Math.max(1, Math.floor(width / (Theme.cardSize + Theme.spaceLg)))
                       * (Theme.cardSize + Theme.spaceLg)
            const max = Math.max(0, contentWidth - width)
            contentX = Math.max(0, Math.min(max, contentX + direction * step))
        }

        Layout.fillWidth: true
        Layout.preferredHeight: Theme.cardSize + 76
        Layout.leftMargin: Theme.spaceLg
        Layout.rightMargin: Theme.spaceLg
        orientation: ListView.Horizontal
        spacing: Theme.spaceLg
        clip: true
        reuseItems: true
        model: root.items
        boundsBehavior: Flickable.StopAtBounds
        // A Flickable swallows the wheel whichever way it points, so a strip
        // that flicked would stop the page under it from scrolling. TIDAL's own
        // carousels move by their arrows, not by dragging, so this matches.
        interactive: false

        Behavior on contentX {
            NumberAnimation { duration: Theme.duration; easing.type: Easing.OutCubic }
        }

        delegate: MediaCard {
            required property var modelData

            // Mixes have no favourite endpoint (see showFavorite below).
            readonly property bool inLibrary: {
                if (!root.favorites || !modelData)
                    return false
                const _revision = root.favorites.revision
                switch (modelData.kind) {
                case "album":    return root.favorites.is_album(Number(modelData.id))
                case "artist":   return root.favorites.is_artist(Number(modelData.id))
                case "playlist": return root.favorites.is_playlist(String(modelData.id))
                default:         return false
                }
            }

            function toggleFavorite() {
                switch (modelData.kind) {
                case "album":    root.favorites.toggle_album(Number(modelData.id)); break
                case "artist":   root.favorites.toggle_artist(Number(modelData.id)); break
                case "playlist": root.favorites.toggle_playlist(String(modelData.id)); break
                }
            }

            title: modelData.title || ""
            subtitle: modelData.subtitle || ""
            image: modelData.image || ""
            kind: modelData.kind || "album"
            favorited: inLibrary
            // Mixes and videos have no favourite endpoint in
            // FavoritesController, so their hearts would do nothing.
            showFavorite: !!root.favorites
                          && ["album", "artist", "playlist"].indexOf(modelData.kind) >= 0
            onFavoriteToggled: toggleFavorite()
            onActivated: root.itemActivated(modelData)
            onPlayRequested: root.itemPlayRequested(modelData)
            onContextRequested: (x, y) => {
                const p = mapToItem(root, x, y)
                root.itemContextRequested(modelData, p.x, p.y)
            }
        }
    }
}
