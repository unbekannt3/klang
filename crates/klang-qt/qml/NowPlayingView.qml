// Full now-playing view. Slides up over the content area; the caller anchors it
// to stop above the player bar, which stays visible and usable.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    required property var player
    property bool open: false
    signal closeRequested()

    // Widens the right pane at the calm left half's expense; a view-local
    // layout choice, not something the rest of the app needs to know about.
    property bool expanded: false
    property int activeTab: 0
    readonly property var tabs: ["Play queue", "Suggested tracks", "Lyrics", "Credits"]

    clip: true

    function parseRows(json) {
        if (typeof json === "string")
            return JSON.parse(json || "[]")
        return json || []
    }

    readonly property var queueRows: root.parseRows(root.player.queue_json)
    readonly property var manualRows: root.queueRows.filter((r) => r.manual)
    readonly property var upcomingRows: root.queueRows.filter((r) => !r.manual)
    // history_json is newest-first (see publish_queue in player.rs); TIDAL
    // lists oldest at the top, so the display order is reversed here.
    readonly property var historyRows: root.parseRows(root.player.history_json).slice().reverse()

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

    readonly property string sourceName: root.player.source_label.length > 0
        ? root.player.source_label : root.sourceLabel(root.player.source)
    readonly property string upcomingHeading: root.sourceName.length > 0
        ? "NEXT UP FROM " + root.sourceName.toUpperCase() : "NEXT UP"

    // Queue entries carry no album field (see Entry in queue.rs), so this
    // degrades to the artist alone until that changes.
    function subtitle(track) {
        return track.album ? track.artist + " · " + track.album : track.artist
    }

    readonly property real sheetHeight: root.height

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
                    text: root.subtitle(row.track)
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textMuted
                }
            }

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

    component CornerButton: Rectangle {
        id: btn
        required property string iconName
        signal activated()

        implicitWidth: 32
        implicitHeight: 32
        radius: Theme.radiusFull
        color: hover.hovered ? Theme.hlMed : "transparent"

        HoverHandler { id: hover }
        TapHandler { onSingleTapped: btn.activated() }

        Icon {
            anchors.centerIn: parent
            width: 16
            height: 16
            name: btn.iconName
            color: hover.hovered ? Theme.textPrimary : Theme.textSecondary
        }
    }

    component TabItem: Item {
        id: tab
        required property string label
        required property bool active
        signal activated()

        implicitWidth: label_.implicitWidth
        implicitHeight: 40

        Text {
            id: label_
            anchors.centerIn: parent
            text: tab.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.weight: tab.active ? Font.DemiBold : Font.Normal
            color: tab.active ? Theme.textPrimary : (hover.hovered ? Theme.textSecondary : Theme.textMuted)
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 2
            radius: 1
            color: Theme.accent
            visible: tab.active
        }

        HoverHandler { id: hover }
        TapHandler { onSingleTapped: tab.activated() }
    }

    component EmptyState: Item {
        id: empty
        required property string message

        Text {
            anchors.centerIn: parent
            width: parent.width - Theme.spaceXl * 2
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: empty.message
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textFaint
        }
    }

    Rectangle {
        id: sheet
        width: root.width
        height: root.sheetHeight
        y: root.open ? 0 : root.sheetHeight
        color: Theme.base

        Behavior on y {
            NumberAnimation { duration: Theme.duration; easing.type: Easing.OutCubic }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            Item {
                id: leftPane
                Layout.preferredWidth: sheet.width * (root.expanded ? 0.3 : 0.5)
                Layout.fillHeight: true

                Behavior on Layout.preferredWidth {
                    NumberAnimation { duration: Theme.duration; easing.type: Easing.OutCubic }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - Theme.spaceXl * 2, 420)
                    spacing: Theme.space

                    CoverArt {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: Math.min(parent.width, sheet.height - Theme.spaceXl * 4)
                        Layout.preferredHeight: Layout.preferredWidth
                        uuid: root.player.cover
                    }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: root.player.title
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeHeading
                        font.weight: Font.Bold
                        color: Theme.textPrimary
                    }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: root.player.artist
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLg
                        color: Theme.textMuted
                    }
                }
            }

            Item {
                id: rightPane
                Layout.fillWidth: true
                Layout.fillHeight: true

                Rectangle {
                    anchors.left: parent.left
                    width: 1
                    height: parent.height
                    color: Theme.border
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 1
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 64
                        spacing: Theme.space

                        Row {
                            Layout.leftMargin: Theme.spaceLg
                            spacing: Theme.spaceLg

                            Repeater {
                                model: root.tabs
                                delegate: TabItem {
                                    required property string modelData
                                    required property int index
                                    label: modelData
                                    active: root.activeTab === index
                                    onActivated: root.activeTab = index
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        CornerButton {
                            iconName: root.expanded ? "restore" : "maximize"
                            onActivated: root.expanded = !root.expanded
                        }

                        CornerButton {
                            Layout.rightMargin: Theme.spaceLg
                            iconName: "close"
                            onActivated: root.closeRequested()
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Theme.border
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Flickable {
                            id: flick
                            anchors.fill: parent
                            visible: root.activeTab === 0
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
                                    visible: root.historyRows.length === 0 && root.player.track_id === 0
                                             && root.manualRows.length === 0 && root.upcomingRows.length === 0
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                    text: "Nothing playing yet"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    color: Theme.textFaint
                                }

                                SectionLabel {
                                    Layout.topMargin: Theme.spaceXl
                                    Layout.leftMargin: Theme.spaceLg
                                    visible: root.historyRows.length > 0
                                    text: "HISTORY"
                                }

                                Repeater {
                                    model: root.historyRows
                                    // A no-op for now: history rows have nothing to jump back to.
                                    delegate: QueueRow {
                                        required property var modelData
                                        Layout.leftMargin: Theme.spaceSm
                                        Layout.rightMargin: Theme.spaceSm
                                        track: modelData
                                        interactive: false
                                    }
                                }

                                SectionLabel {
                                    Layout.topMargin: Theme.space
                                    Layout.leftMargin: Theme.spaceLg
                                    visible: root.player.track_id !== 0
                                    text: "NOW PLAYING"
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

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: Theme.space
                                    Layout.leftMargin: Theme.spaceLg
                                    Layout.rightMargin: Theme.spaceLg
                                    visible: root.manualRows.length > 0 || root.upcomingRows.length > 0

                                    SectionLabel {
                                        Layout.fillWidth: true
                                        text: root.upcomingHeading
                                    }

                                    Text {
                                        visible: root.manualRows.length > 0
                                        text: "Clear"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSm
                                        color: clearHover.hovered ? Theme.textPrimary : Theme.textMuted

                                        HoverHandler { id: clearHover }
                                        TapHandler { onSingleTapped: root.player.clear_queue() }
                                    }
                                }

                                SectionLabel {
                                    Layout.topMargin: Theme.spaceXs
                                    Layout.leftMargin: Theme.spaceLg
                                    visible: root.manualRows.length > 0
                                    text: "NEXT IN QUEUE"
                                }

                                // Index is the row's position within manualRows itself, matching
                                // jump_to's "manual" list — same convention as QueuePanel.
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

                        // Nothing in klang-core's facade feeds these yet (see report):
                        // no per-track radio, and metadata.rs's lyrics/credits calls
                        // are not exposed through any qml_element.
                        EmptyState {
                            anchors.fill: parent
                            visible: root.activeTab === 1
                            message: "Suggested tracks aren't available yet"
                        }

                        EmptyState {
                            anchors.fill: parent
                            visible: root.activeTab === 2
                            message: "Lyrics aren't available yet"
                        }

                        EmptyState {
                            anchors.fill: parent
                            visible: root.activeTab === 3
                            message: "Credits aren't available yet"
                        }
                    }
                }
            }
        }
    }
}
