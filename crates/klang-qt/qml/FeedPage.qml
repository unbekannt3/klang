// Activity feed: new releases from followed artists and playlists, grouped
// by day.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    required property var player
    required property int userId

    signal openAlbum(int albumId)
    signal openArtist(int artistId)
    signal openPlaylist(string uuid, string title)

    FeedController { id: feed }

    function groups() {
        return JSON.parse(feed.items_json || "[]")
    }

    // Unknown-kind rows (see feed.rs) render for visibility but don't navigate.
    function activate(item) {
        if (item.kind === "album")
            root.openAlbum(parseInt(item.id))
        else if (item.kind === "mix")
            root.openPlaylist(item.id, item.title)
    }

    function reload() {
        if (userId === 0)
            return
        feed.load(userId)
        feed.mark_seen(userId)
    }

    onUserIdChanged: reload()
    Component.onCompleted: reload()

    Rectangle { anchors.fill: parent; color: Theme.base }

    // One card, plus a corner dot for unseen items. MediaCard has no notion
    // of "seen", so this overlays rather than touching that component.
    component FeedCard: Item {
        id: cardRoot

        property string title: ""
        property string subtitle: ""
        property string image: ""
        property string kind: "album"
        property bool seen: true

        signal activated()

        implicitWidth: Theme.cardSize
        implicitHeight: Theme.cardSize + 52

        MediaCard {
            anchors.fill: parent
            title: cardRoot.title
            subtitle: cardRoot.subtitle
            image: cardRoot.image
            kind: cardRoot.kind
            onActivated: cardRoot.activated()
        }

        Rectangle {
            visible: !cardRoot.seen
            width: 10
            height: 10
            radius: 5
            color: Theme.accent
            border.width: 2
            border.color: Theme.base
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Theme.spaceXs
        }
    }

    ListView {
        id: view
        anchors.fill: parent
        clip: true
        model: root.groups()
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

        // A day's worth of activity is usually a handful of releases, not a
        // long strip worth paging arrows for — a wrapping flow keeps every
        // card visible at once, and (unlike CardCarousel's fixed delegate)
        // leaves room for the unseen marker on each one.
        delegate: ColumnLayout {
            required property var modelData

            width: view.width
            spacing: Theme.spaceSm

            Text {
                Layout.leftMargin: Theme.spaceLg
                Layout.rightMargin: Theme.spaceLg
                text: modelData.label || ""
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeHeading
                font.weight: Font.Bold
                color: Theme.textPrimary
            }

            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spaceLg
                Layout.rightMargin: Theme.spaceLg
                spacing: Theme.spaceLg

                Repeater {
                    model: modelData.items || []

                    delegate: FeedCard {
                        required property var modelData

                        title: modelData.title || ""
                        subtitle: modelData.subtitle || ""
                        image: modelData.image || ""
                        kind: modelData.kind || "album"
                        seen: !!modelData.seen
                        onActivated: root.activate(modelData)
                    }
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: view.count === 0 && !feed.loading
        text: feed.error.length > 0 ? feed.error : "Nothing here yet"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeLg
        color: Theme.textFaint
    }

    QQC2.BusyIndicator {
        anchors.centerIn: parent
        running: feed.loading
    }
}
