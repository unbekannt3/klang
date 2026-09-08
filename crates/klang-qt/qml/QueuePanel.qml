// Right-hand queue drawer over the content area, TIDAL-style: the currently
// playing track pinned at the top, then manual queue picks, then the context.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    required property var player
    property bool open: false
    signal closeRequested()

    readonly property int panelWidth: 340

    function rows() {
        if (typeof player.queue_json === "string")
            return JSON.parse(player.queue_json || "[]")
        return player.queue_json || []
    }

    // queue_json already excludes the playing track (see publish_queue in
    // player.rs), so the two groups below are exactly what filtering leaves.
    readonly property var queueRows: root.rows()
    readonly property var manualRows: root.queueRows.filter((r) => r.manual)
    readonly property var upcomingRows: root.queueRows.filter((r) => !r.manual)

    // `source` only carries a kind and an id ("playlist:<uuid>"), never a
    // title, so a playlist or album queue can only be labelled by its kind.
    function sourceLabel(source) {
        if (!source)
            return ""
        const kind = source.split(":")[0]
        const names = {
            favorites: "Favorites", playlist: "Playlist", album: "Album",
            artist: "Artist", mix: "Mix", search: "Search",
        }
        return names[kind] || (kind.charAt(0).toUpperCase() + kind.slice(1))
    }

    component SectionLabel: Text {
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm - 1
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
        color: Theme.textFaint
    }

    component QueueRow: Rectangle {
        id: row
        required property var track
        property bool active: false
        property bool interactive: true
        property bool removable: false
        signal activated()
        signal removeRequested()

        Layout.fillWidth: true
        Layout.preferredHeight: Theme.rowHeight
        radius: Theme.radiusXs
        color: hover.hovered && row.interactive ? Theme.hlFaint : "transparent"

        HoverHandler { id: hover }
        TapHandler { enabled: row.interactive; onSingleTapped: row.activated() }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spaceSm
            anchors.rightMargin: Theme.spaceSm
            spacing: Theme.spaceSm

            CoverArt {
                Layout.preferredWidth: Theme.coverThumb
                Layout.preferredHeight: Theme.coverThumb
                uuid: row.track.cover || ""
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: row.track.title
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: row.active ? Theme.accent : Theme.textPrimary
                }

                Text {
                    Layout.fillWidth: true
                    text: row.track.artist
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textMuted
                }
            }

            // Duration gives way to a remove button on hover, manual rows only.
            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 28

                Text {
                    anchors.centerIn: parent
                    visible: !(row.removable && hover.hovered)
                    text: Format.duration(row.track.duration)
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textFaint
                }

                Rectangle {
                    anchors.centerIn: parent
                    visible: row.removable && hover.hovered
                    width: 26
                    height: 26
                    radius: Theme.radiusFull
                    color: removeHover.hovered ? Theme.hlMed : "transparent"

                    HoverHandler { id: removeHover }
                    TapHandler { onSingleTapped: row.removeRequested() }

                    Icon {
                        anchors.centerIn: parent
                        width: 13
                        height: 13
                        name: "close"
                        color: Theme.textSecondary
                    }
                }
            }
        }
    }

    // Scrim over the content area behind the drawer.
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.open ? 0.4 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.duration }
        }

        TapHandler { onTapped: root.closeRequested() }
    }

    Rectangle {
        id: panel
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        // Slides fully off-screen at rightMargin == -width rather than moving
        // the panel's x, so anchoring to the edge still works mid-animation.
        anchors.rightMargin: root.open ? 0 : -width
        width: root.panelWidth
        color: Theme.elevated

        Behavior on anchors.rightMargin {
            NumberAnimation { duration: Theme.duration; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.left: parent.left
            width: 1
            height: parent.height
            color: Theme.border
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 64

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spaceLg
                    anchors.rightMargin: Theme.spaceLg
                    spacing: Theme.space

                    Text {
                        text: "Queue"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeHeading
                        font.weight: Font.Bold
                        color: Theme.textPrimary
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        visible: root.manualRows.length > 0
                        text: "Clear"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        color: clearHover.hovered ? Theme.textPrimary : Theme.textMuted

                        HoverHandler { id: clearHover }
                        TapHandler { onSingleTapped: root.player.clear_queue() }
                    }

                    Rectangle {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: Theme.radiusFull
                        color: closeHover.hovered ? Theme.hlMed : "transparent"

                        HoverHandler { id: closeHover }
                        TapHandler { onSingleTapped: root.closeRequested() }

                        Icon {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            name: "close"
                            color: Theme.textSecondary
                        }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Theme.border
                }
            }

            Flickable {
                id: flick
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: content.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                HoverHandler { id: flickHover }

                WheelScroller {
                    view: flick
                    rowHeight: Theme.rowHeight
                }

                QQC2.ScrollBar.vertical: ThemedScrollBar {
                    listHovered: flickHover.hovered
                }

                ColumnLayout {
                    id: content
                    width: flick.width
                    spacing: Theme.spaceXs

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spaceXl
                        Layout.leftMargin: Theme.spaceLg
                        Layout.rightMargin: Theme.spaceLg
                        visible: root.player.track_id === 0 && root.manualRows.length === 0
                                 && root.upcomingRows.length === 0
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: "Queue is empty"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        color: Theme.textFaint
                    }

                    SectionLabel {
                        Layout.topMargin: Theme.space
                        Layout.leftMargin: Theme.spaceLg
                        visible: root.player.track_id !== 0 && root.sourceLabel(root.player.source).length > 0
                        text: "PLAYING FROM " + root.sourceLabel(root.player.source).toUpperCase()
                    }

                    QueueRow {
                        Layout.leftMargin: Theme.spaceSm
                        Layout.rightMargin: Theme.spaceSm
                        visible: root.player.track_id !== 0
                        active: true
                        interactive: false
                        track: ({
                            title: root.player.title, artist: root.player.artist,
                            cover: root.player.cover, duration: root.player.duration_secs,
                        })
                    }

                    SectionLabel {
                        Layout.topMargin: Theme.space
                        Layout.leftMargin: Theme.spaceLg
                        visible: root.manualRows.length > 0
                        text: "NEXT IN QUEUE"
                    }

                    Repeater {
                        model: root.manualRows
                        delegate: QueueRow {
                            required property var modelData
                            required property int index
                            Layout.leftMargin: Theme.spaceSm
                            Layout.rightMargin: Theme.spaceSm
                            track: modelData
                            removable: true
                            onActivated: root.player.jump_to(index, true)
                            onRemoveRequested: root.player.remove_queued(index)
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spaceSm
                        Layout.leftMargin: Theme.spaceLg
                        Layout.rightMargin: Theme.spaceLg
                        visible: root.manualRows.length > 0 && root.upcomingRows.length > 0
                        height: 1
                        color: Theme.border
                    }

                    SectionLabel {
                        Layout.topMargin: Theme.space
                        Layout.leftMargin: Theme.spaceLg
                        visible: root.upcomingRows.length > 0
                        text: "NEXT UP"
                    }

                    Repeater {
                        model: root.upcomingRows
                        delegate: QueueRow {
                            required property var modelData
                            required property int index
                            Layout.leftMargin: Theme.spaceSm
                            Layout.rightMargin: Theme.spaceSm
                            track: modelData
                            onActivated: root.player.jump_to(index, false)
                        }
                    }

                    Item { Layout.preferredHeight: Theme.spaceLg }
                }
            }
        }
    }
}
