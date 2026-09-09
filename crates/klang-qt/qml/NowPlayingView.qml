// Full now-playing view. Slides up over the content area; the caller anchors it
// to stop above the player bar, which stays visible and usable.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    required property var player
    property var favorites: null
    /// Bubbles a suggested row's right-click up to the window's shared menu.
    signal trackContextRequested(var track, real x, real y)
    property bool open: false
    signal closeRequested()

    // Widens the right pane at the calm left half's expense; a view-local
    // layout choice, not something the rest of the app needs to know about.
    property bool expanded: false
    property int activeTab: 0
    readonly property var tabs: [Tr.t("Play queue"), Tr.t("Suggested tracks"),
                                 Tr.t("Lyrics"), Tr.t("Credits")]

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
    NowPlayingController { id: panels }

    // Only fetch while the sheet is open: a background window has no reason
    // to pull lyrics for every track that plays.
    function refreshPanels() {
        if (root.open)
            panels.load(root.player.track_id)
    }

    onOpenChanged: refreshPanels()

    Connections {
        target: root.player
        function onTrack_idChanged() { root.refreshPanels() }
    }

    readonly property var historyRows: root.parseRows(root.player.history_json).slice().reverse()

    function sourceLabel(source) {
        if (!source)
            return ""
        const kind = source.split(":")[0]
        const names = {
            favorites: "Favorites", playlist: "Playlist", album: "Album",
            artist: "Artist", mix: "Mix", search: "Search", radio: "Radio",
        }
        return Tr.t(names[kind] || (kind.charAt(0).toUpperCase() + kind.slice(1)))
    }

    readonly property string sourceName: root.player.source_label.length > 0
        ? root.player.source_label : root.sourceLabel(root.player.source)
    readonly property string upcomingHeading: root.sourceName.length > 0
        ? Tr.t("NEXT UP FROM %1").arg(root.sourceName.toUpperCase())
        : Tr.t("NEXT UP")

    // History, now playing and the two up-next lists flattened into one model
    // so a ListView can virtualize the lot. As three Repeaters in a column, a
    // 300-track radio built 300 rows and asked the CDN for 300 covers at once.
    readonly property var queueModel: {
        const rows = []

        if (root.historyRows.length > 0)
            rows.push({ type: "label", gap: Theme.spaceXl, text: Tr.t("HISTORY") })
        // History rows are a no-op: there is nothing to jump back to.
        for (const t of root.historyRows)
            rows.push({ type: "track", track: t, mode: "history" })

        if (root.player.track_id !== 0) {
            rows.push({ type: "label", gap: Theme.space, text: Tr.t("NOW PLAYING") })
            rows.push({ type: "track", mode: "current", track: {
                title: root.player.title, artist: root.player.artist,
                cover: root.player.cover, duration: root.player.duration_secs,
            } })
        }

        const manual = root.manualRows
        const upcoming = root.upcomingRows
        if (manual.length > 0 || upcoming.length > 0)
            rows.push({ type: "heading", gap: Theme.space, text: root.upcomingHeading,
                        clearable: manual.length > 0 })

        if (manual.length > 0) {
            rows.push({ type: "label", gap: Theme.spaceXs, text: Tr.t("NEXT IN QUEUE") })
            // Index is the row's position within manualRows itself, matching
            // jump_to's "manual" list — same convention as QueuePanel.
            manual.forEach((t, i) => rows.push({ type: "track", track: t, mode: "manual", index: i }))
            if (upcoming.length > 0)
                rows.push({ type: "divider" })
        }
        upcoming.forEach((t, i) => rows.push({ type: "track", track: t, mode: "upcoming", index: i }))

        return rows
    }

    function entryHeight(entry) {
        switch (entry.type) {
        case "track":   return Theme.rowHeight
        case "label":   return entry.gap + 18
        case "heading": return entry.gap + 22
        }
        return Theme.spaceSm * 2 + 1
    }

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
        /// Right-click, in this row's coordinates.
        signal contextRequested(real x, real y)

        implicitHeight: Theme.rowHeight
        radius: Theme.radiusXs
        color: hover.hovered && row.interactive ? Theme.hlFaint : "transparent"

        HoverHandler { id: hover }
        TapHandler { enabled: row.interactive; onSingleTapped: row.activated() }

        // The playing row gets one too; `interactive` only governs jumping.
        TapHandler {
            acceptedButtons: Qt.RightButton
            onSingleTapped: (event) =>
                row.contextRequested(event.position.x, event.position.y)
        }

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
                    font.family: Theme.fontFamilyMono
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

    /// TIDAL returns plain lyrics and, for some tracks, an LRC subtitle
    /// track. klang shows the plain text: without a synced view the
    /// timestamps are noise.
    function lyricsText() {
        if (panels.lyrics.length > 0)
            return panels.lyrics
        return panels.loading ? "" : "No lyrics for this track"
    }

    /// Parsed once rather than per binding that reads it.
    readonly property var creditRows: JSON.parse(panels.credits_json || "[]")

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

        CoverWash {
            anchors.fill: parent
            uuid: root.player.cover
        }

        // Taps would otherwise land on the window buttons behind the sheet —
        // the close glyph sits right over the one that quits the app.
        ModalShield { blocksPage: true }

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
                    width: Math.min(parent.width - Theme.spaceXl * 2, 560)
                    spacing: Theme.space

                    CoverArt {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: Math.min(parent.width,
                                                        sheet.height - Theme.spaceXl * 2)
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
                        // Over the strongest part of the wash, so a tier up.
                        color: Theme.textSecondary
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

                    // Only the visible tab exists: the suggestions list, the
                    // lyrics and the credits are all per-track fetches nobody
                    // asked for until they switch to them.
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ListView {
                            id: queueList
                            anchors.fill: parent
                            visible: root.activeTab === 0
                            clip: true
                            model: root.queueModel
                            topMargin: Theme.spaceXl
                            bottomMargin: Theme.spaceLg
                            boundsBehavior: Flickable.StopAtBounds
                            reuseItems: true

                            HoverHandler { id: queueHover }

                            WheelScroller {
                                view: queueList
                                rowHeight: Theme.rowHeight
                            }

                            QQC2.ScrollBar.vertical: ThemedScrollBar {
                                listHovered: queueHover.hovered
                            }

                            delegate: Item {
                                id: entry
                                required property var modelData

                                width: queueList.width
                                height: root.entryHeight(entry.modelData)

                                Loader {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spaceSm
                                    anchors.rightMargin: Theme.spaceSm
                                    active: entry.modelData.type === "track"

                                    sourceComponent: QueueRow {
                                        readonly property string mode: entry.modelData.mode
                                        track: entry.modelData.track
                                        active: mode === "current"
                                        interactive: mode === "manual" || mode === "upcoming"
                                        removable: mode === "manual"
                                        onActivated: root.player.jump_to(entry.modelData.index,
                                                                        mode === "manual")
                                        onRemoveRequested: root.player.remove_queued(entry.modelData.index)
                                        onContextRequested: (x, y) => {
                                            const p = mapToItem(root, x, y)
                                            root.trackContextRequested(entry.modelData.track,
                                                                       p.x, p.y)
                                        }
                                    }
                                }

                                // A Loader resizes its item to its own size, so
                                // anything anchored inside sits in a wrapper.
                                Loader {
                                    anchors.fill: parent
                                    active: entry.modelData.type === "label"

                                    sourceComponent: Item {
                                        SectionLabel {
                                            anchors.left: parent.left
                                            anchors.bottom: parent.bottom
                                            anchors.leftMargin: Theme.spaceLg
                                            text: entry.modelData.text
                                        }
                                    }
                                }

                                Loader {
                                    anchors.fill: parent
                                    active: entry.modelData.type === "heading"

                                    sourceComponent: Item {
                                        RowLayout {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.leftMargin: Theme.spaceLg
                                            anchors.rightMargin: Theme.spaceLg

                                            SectionLabel {
                                                Layout.fillWidth: true
                                                text: entry.modelData.text
                                            }

                                            Text {
                                                visible: entry.modelData.clearable
                                                text: Tr.t("Clear")
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeSm
                                                color: clearHover.hovered ? Theme.textPrimary
                                                                          : Theme.textMuted

                                                HoverHandler { id: clearHover }
                                                TapHandler { onSingleTapped: root.player.clear_queue() }
                                            }
                                        }
                                    }
                                }

                                Loader {
                                    anchors.fill: parent
                                    active: entry.modelData.type === "divider"

                                    sourceComponent: Item {
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.leftMargin: Theme.spaceLg
                                            anchors.rightMargin: Theme.spaceLg
                                            height: 1
                                            color: Theme.border
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: Theme.spaceXl
                            width: parent.width - Theme.spaceLg * 2
                            visible: root.activeTab === 0 && root.queueModel.length === 0
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: Tr.t("Nothing playing yet")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            color: Theme.textFaint
                        }

                        Loader {
                            anchors.fill: parent
                            active: root.activeTab === 1

                            sourceComponent: TrackList {
                                tracks: panels.suggested_json
                                loading: panels.loading
                                activeId: root.player.track_id
                                favorites: root.favorites
                                showBpm: false
                                showKey: false
                                emptyText: Tr.t("No suggestions for this track")
                                onTrackActivated: (index) =>
                                        root.player.play_context(panels.suggested_json, index,
                                                                 "radio:" + root.player.track_id)
                                onContextRequested: (index, x, y) => {
                                    const rows = JSON.parse(panels.suggested_json || "[]")
                                    if (rows[index])
                                        root.trackContextRequested(rows[index], x, y)
                                }
                            }
                        }

                        Loader {
                            anchors.fill: parent
                            anchors.margins: Theme.spaceLg
                            active: root.activeTab === 2

                            sourceComponent: Flickable {
                                id: lyricsFlick
                                contentHeight: lyricsText.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                WheelScroller {
                                    view: lyricsFlick
                                    rowHeight: Theme.rowHeight
                                }

                                QQC2.ScrollBar.vertical: ThemedScrollBar {
                                    listHovered: lyricsHover.hovered
                                }

                                HoverHandler { id: lyricsHover }

                                Text {
                                    id: lyricsText
                                    width: lyricsFlick.width
                                    text: root.lyricsText()
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.5
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeLg
                                    color: panels.lyrics.length > 0 ? Theme.textPrimary : Theme.textFaint
                                }
                            }
                        }

                        Loader {
                            anchors.fill: parent
                            anchors.margins: Theme.spaceLg
                            active: root.activeTab === 3

                            sourceComponent: Flickable {
                                id: creditsFlick
                                contentHeight: creditsColumn.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                WheelScroller {
                                    view: creditsFlick
                                    rowHeight: Theme.rowHeight
                                }

                                QQC2.ScrollBar.vertical: ThemedScrollBar {
                                    listHovered: creditsHover.hovered
                                }

                                HoverHandler { id: creditsHover }

                                ColumnLayout {
                                    id: creditsColumn
                                    width: creditsFlick.width
                                    spacing: Theme.space

                                    Repeater {
                                        model: root.creditRows

                                        ColumnLayout {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: 2

                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.role
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeSm
                                                color: Theme.textFaint
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.contributors.join(", ")
                                                wrapMode: Text.WordWrap
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSize
                                                color: Theme.textPrimary
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        visible: root.creditRows.length === 0
                                        horizontalAlignment: Text.AlignHCenter
                                        text: panels.loading ? "" : "No credits for this track"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize
                                        color: Theme.textFaint
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
