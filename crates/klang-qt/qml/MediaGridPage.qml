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

    signal openAlbum(int albumId)
    signal openArtist(int artistId)
    signal openPlaylist(string uuid, string title)
    signal openMix(string mixId, string title)

    function rows() {
        if (typeof items === "string")
            return JSON.parse(items || "[]")
        return items || []
    }

    // Kinds without a dedicated page (e.g. a future "video" favourite) fall
    // back to playing the item directly, same as SectionList's carousels.
    function activate(item) {
        switch (item.kind) {
        case "album":
            root.openAlbum(parseInt(item.id))
            break
        case "artist":
            root.openArtist(parseInt(item.id))
            break
        case "playlist":
            root.openPlaylist(item.id, item.title)
            break
        case "mix":
            root.openMix(item.id, item.title)
            break
        default:
            root.player.play(parseInt(item.id), item.title, item.subtitle, 0, item.image)
        }
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
                clip: true
                model: root.rows()
                reuseItems: true

                // At least one column; more once the width fits another card
                // plus its gutter. Cells then stretch to fill each row evenly.
                readonly property int columns: Math.max(1, Math.floor(width / (Theme.cardSize + Theme.spaceLg)))
                cellWidth: width / columns
                cellHeight: Theme.cardSize + 52 + Theme.spaceLg

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
                        anchors.rightMargin: Theme.spaceLg
                        anchors.bottomMargin: Theme.spaceLg
                        title: cell.modelData.title || ""
                        subtitle: cell.modelData.subtitle || ""
                        image: cell.modelData.image || ""
                        kind: cell.modelData.kind || "album"
                        onActivated: root.activate(cell.modelData)
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: grid.count === 0 && !root.loading
                text: root.error.length > 0 ? root.error : "Nothing here"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLg
                color: Theme.textFaint
            }

            QQC2.BusyIndicator {
                anchors.centerIn: parent
                running: root.loading
            }
        }
    }
}
