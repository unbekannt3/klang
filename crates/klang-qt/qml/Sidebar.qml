// Left navigation rail. 220 px, matching tidal.com.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

Rectangle {
    id: root

    /// Route key of the visible page.
    property string current: "home"
    /// JSON string or array from PlaylistsController.playlists_json.
    property var playlists: []

    // Folder/playlist mutations (create, rename, delete, move, edit) land on
    // this private controller rather than Main.qml's shared one — that way
    // the sidebar's write path needs no change to how Main.qml wires
    // `playlists` in. The moment it first refreshes, its own json becomes
    // the source of truth ahead of whatever `playlists` was last fed.
    PlaylistsController { id: writer }
    readonly property bool writerReady: writer.playlists_json.length > 0
    readonly property var displaySource: root.writerReady ? writer.playlists_json : root.playlists

    // Folders default open; collapsing one records `false` here. Keyed by
    // folder id, reassigned wholesale on toggle since QML bindings only
    // react to property reassignment, not in-place object mutation.
    property var collapsed: ({})

    signal navigate(string route)
    signal openPlaylist(string uuid, string title)

    /// Collapsed to an icon rail, as tidal.com's toggle does.
    property bool collapsedRail: false
    readonly property int railWidth: 68

    implicitWidth: root.collapsedRail ? root.railWidth : Theme.sidebarWidth
    color: Theme.sidebar

    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.duration; easing.type: Easing.OutCubic }
    }

    function allRows() {
        const source = root.displaySource
        return typeof source === "string"
             ? JSON.parse(source || "[]")
             : (source || [])
    }

    function folderRows() {
        return root.allRows().filter((r) => r.kind === "folder")
    }

    function isExpanded(id) {
        return root.collapsed[id] !== true
    }

    function toggleFolder(id) {
        const next = Object.assign({}, root.collapsed)
        next[id] = root.isExpanded(id)
        root.collapsed = next
    }

    /// "all" | "mine" | "others" — tidal.com separates the playlists you
    /// made from the ones you follow.
    property string playlistFilter: "all"
    /// "updated" | "created" | "name"
    property string playlistSort: "updated"
    /// Whose playlists count as yours.
    property int userId: 0

    function matchesFilter(playlist) {
        if (root.playlistFilter === "all")
            return true
        const mine = root.userId !== 0 && playlist.ownerId === root.userId
        return root.playlistFilter === "mine" ? mine : !mine
    }

    function sorted(playlists) {
        const by = root.playlistSort
        return playlists.slice().sort((a, b) => {
            if (by === "name")
                return (a.title || "").localeCompare(b.title || "")
            const key = by === "created" ? "created" : "updated"
            return (b[key] || "").localeCompare(a[key] || "")
        })
    }

    /// Flattens folders and their playlists into one display list — a
    /// folder header row followed by its playlists when expanded, then
    /// every playlist that isn't inside a folder.
    function treeRows() {
        const all = root.allRows()
        const folders = all.filter((r) => r.kind === "folder")
        const items = root.sorted(all.filter((r) => r.kind === "playlist"
                                                    && root.matchesFilter(r)))
        const rows = []

        for (const f of folders) {
            rows.push({
                kind: "folder", id: f.id, name: f.name, trackCount: f.trackCount,
                expanded: root.isExpanded(f.id),
            })
            if (root.isExpanded(f.id)) {
                for (const p of items.filter((p) => p.parent === f.id))
                    rows.push(Object.assign({ depth: 1 }, p))
            }
        }
        for (const p of items.filter((p) => !p.parent))
            rows.push(Object.assign({ depth: 0 }, p))

        return rows
    }

    function openFolderMenu(folder, point) {
        folderMenu.model = [
            { label: Tr.t("Rename folder"), onTriggered: () => namePrompt.showAt(Tr.t("Rename folder"), "rename", folder.id, folder.name) },
            { separator: true },
            { label: Tr.t("Delete folder"), danger: true, onTriggered: () => writer.delete_folder(folder.id) },
        ]
        folderMenu.openAt(point, root)
    }

    function openPlaylistMenu(playlist, point) {
        const moveEntries = []
        if (playlist.parent)
            moveEntries.push({ label: Tr.t("Top level"), onTriggered: () => writer.move_to_folder(playlist.id, "") })
        for (const f of root.folderRows()) {
            if (f.id === playlist.parent)
                continue
            moveEntries.push({ label: f.name, onTriggered: () => writer.move_to_folder(playlist.id, f.id) })
        }

        const items = [
            { label: Tr.t("Edit playlist"), onTriggered: () => root.openEditDialog(playlist) },
        ]
        if (moveEntries.length > 0)
            items.push({ label: Tr.t("Move to folder"), submenu: moveEntries })
        items.push({ separator: true })
        items.push({ label: Tr.t("Delete playlist"), danger: true, onTriggered: () => writer.remove(playlist.id) })

        playlistMenu.model = items
        playlistMenu.openAt(point, root)
    }

    function openEditDialog(playlist) {
        // Sidebar itself is only 220px wide, so the dialog has to live on
        // the window's overlay to centre over the whole app — same trick
        // ContextMenu's openAt() uses.
        editDialog.parent = QQC2.Overlay.overlay
        editDialog.load(playlist.id, playlist.title, playlist.description || "", !!playlist["public"])
        editDialog.open = true
    }

    component NavItem: QQC2.ItemDelegate {
        id: item
        required property string route
        required property string label
        required property string iconName

        Layout.fillWidth: true
        height: 40
        hoverEnabled: true

        background: Rectangle {
            radius: Theme.radiusSm
            color: root.current === item.route ? Theme.hlMed
                 : item.hovered ? Theme.hlFaint
                 : "transparent"
        }

        QQC2.ToolTip {
            visible: root.collapsedRail && item.hovered
            delay: 400
            text: item.label
        }

        contentItem: RowLayout {
            spacing: Theme.spaceSm

            Icon {
                Layout.leftMargin: root.collapsedRail ? 0 : Theme.spaceSm
                Layout.alignment: root.collapsedRail ? Qt.AlignHCenter : Qt.AlignLeft
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                name: item.iconName
                color: root.current === item.route ? Theme.textPrimary : Theme.textMuted
            }

            Text {
                Layout.fillWidth: true
                visible: !root.collapsedRail
                text: item.label
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.weight: root.current === item.route ? Font.DemiBold : Font.Normal
                color: root.current === item.route ? Theme.textPrimary : Theme.textSecondary
            }
        }

        onClicked: root.navigate(item.route)
    }

    // Modal single-line prompt shared by "new folder" and "rename folder" —
    // a Popup rather than a plain Item, since the sidebar's own bounds are
    // only 220px wide and this needs to sit centred over the whole window.


    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spaceSm
        spacing: Theme.spaceSm

        // Wordmark
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spaceSm
            Layout.leftMargin: Theme.spaceSm
            Layout.bottomMargin: Theme.spaceSm
            spacing: Theme.spaceSm

            Image {
                source: "qrc:/qt/qml/me/unbk/klang/qml/klang.png"
                sourceSize.width: 24
                sourceSize.height: 24
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                smooth: true
            }

            Text {
                Layout.fillWidth: true
                visible: !root.collapsedRail
                text: "klang"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLg
                font.weight: Font.Bold
                font.letterSpacing: 1
                color: Theme.textPrimary
            }

            Item {
                implicitWidth: 24
                implicitHeight: 24

                Icon {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    name: root.collapsedRail ? "forward" : "back"
                    color: railHover.hovered ? Theme.textPrimary : Theme.textFaint
                }

                HoverHandler { id: railHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onSingleTapped: root.collapsedRail = !root.collapsedRail }

                QQC2.ToolTip {
                    visible: railHover.hovered
                    delay: 500
                    text: root.collapsedRail ? Tr.t("Expand sidebar") : Tr.t("Collapse sidebar")
                }
            }
        }

        NavItem { route: "home";      label: Tr.t("Home");         iconName: "home" }
        NavItem { route: "explore";   label: Tr.t("Explore");      iconName: "explore" }
        NavItem { route: "feed";      label: Tr.t("Feed");         iconName: "queue" }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spaceSm
            height: 1
            color: Theme.border
        }

        Text {
            Layout.leftMargin: Theme.spaceSm
            visible: !root.collapsedRail
            text: Tr.t("MY COLLECTION")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm - 1
            font.weight: Font.DemiBold
            font.letterSpacing: 1.2
            color: Theme.textFaint
        }

        NavItem { route: "favorites";     label: Tr.t("Tracks");    iconName: "heart" }
        NavItem { route: "fav-albums";    label: Tr.t("Albums");    iconName: "album" }
        NavItem { route: "fav-artists";   label: Tr.t("Artists");   iconName: "artist" }
        NavItem { route: "fav-playlists"; label: Tr.t("Playlists"); iconName: "playlist" }
        NavItem { route: "fav-videos";    label: Tr.t("Videos");    iconName: "video" }
        NavItem { route: "fav-mixes";     label: Tr.t("Mixes");     iconName: "radio" }
        NavItem { route: "settings";      label: Tr.t("Settings");  iconName: "settings" }

        // Divider
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spaceSm
            Layout.bottomMargin: Theme.spaceXs
            height: 1
            color: Theme.border
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spaceSm
            Layout.rightMargin: Theme.spaceXs

            Text {
                Layout.fillWidth: true
                visible: !root.collapsedRail
                text: Tr.t("PLAYLISTS")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm - 1
                font.weight: Font.DemiBold
                font.letterSpacing: 1.2
                color: Theme.textFaint
            }

            // Sort and filter, as tidal.com's own playlist rail has.
            Item {
                implicitWidth: 20
                implicitHeight: 20

                HoverHandler { id: sortHover }
                TapHandler {
                    onSingleTapped: (event) =>
                        playlistSortMenu.openAt(Qt.point(event.position.x, event.position.y),
                                                parent)
                }

                Icon {
                    anchors.centerIn: parent
                    width: 15
                    height: 15
                    name: "more"
                    color: sortHover.hovered ? Theme.textPrimary : Theme.textFaint
                }
            }

            Item {
                // Icon.qml has no plain "+" glyph and is off-limits here, so
                // this is a Text glyph rather than a drawn vector icon.
                implicitWidth: 20
                implicitHeight: 20

                HoverHandler { id: addFolderHover }
                TapHandler { onSingleTapped: namePrompt.showAt(Tr.t("New folder"), "create", "", "") }

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeLg
                    color: addFolderHover.hovered ? Theme.textPrimary : Theme.textFaint
                }
            }
        }

            ContextMenu {
            id: playlistSortMenu
            model: [
                { label: Tr.t("Recently updated"), checked: root.playlistSort === "updated",
                  onTriggered: () => root.playlistSort = "updated" },
                { label: Tr.t("Recently created"), checked: root.playlistSort === "created",
                  onTriggered: () => root.playlistSort = "created" },
                { label: Tr.t("Alphabetical"), checked: root.playlistSort === "name",
                  onTriggered: () => root.playlistSort = "name" },
                { separator: true },
                { label: Tr.t("All playlists"), checked: root.playlistFilter === "all",
                  onTriggered: () => root.playlistFilter = "all" },
                { label: Tr.t("Your playlists"), checked: root.playlistFilter === "mine",
                  onTriggered: () => root.playlistFilter = "mine" },
                { label: Tr.t("Other playlists"), checked: root.playlistFilter === "others",
                  onTriggered: () => root.playlistFilter = "others" },
            ]
        }

    ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            id: playlistView
            bottomMargin: Theme.contentBottomInset
            clip: true
            model: root.treeRows()
            reuseItems: true
            spacing: 1

            HoverHandler { id: playlistHover }

            WheelScroller {
                view: playlistView
                rowHeight: 44
            }

            QQC2.ScrollBar.vertical: ThemedScrollBar {
                listHovered: playlistHover.hovered
            }

            delegate: QQC2.ItemDelegate {
                id: row
                required property var modelData
                readonly property bool isFolder: modelData.kind === "folder"

                width: ListView.view.width
                height: 44
                hoverEnabled: true

                background: Rectangle {
                    radius: Theme.radiusSm
                    color: row.hovered ? Theme.hlFaint : "transparent"
                }

                contentItem: RowLayout {
                    spacing: Theme.spaceSm
                    Layout.leftMargin: (row.modelData.depth || 0) * Theme.space

                    Icon {
                        visible: row.isFolder
                        Layout.leftMargin: Theme.spaceXs
                        Layout.preferredWidth: 14
                        Layout.preferredHeight: 14
                        name: "forward"
                        rotation: row.modelData.expanded ? 90 : 0
                        color: Theme.textFaint

                        Behavior on rotation { NumberAnimation { duration: Theme.durationFast } }
                    }

                    CoverArt {
                        visible: !row.isFolder
                        Layout.leftMargin: Theme.spaceXs
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        uuid: row.isFolder ? "" : (row.modelData.image || "")
                        placeholderGlyph: "≡"
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            text: row.isFolder ? row.modelData.name : row.modelData.title
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.weight: row.isFolder ? Font.DemiBold : Font.Normal
                            color: row.isFolder ? Theme.textPrimary : Theme.textSecondary
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: row.modelData.trackCount > 0
                            text: Tr.t(row.isFolder ? "%1 playlists" : "%1 tracks")
                                    .arg(row.modelData.trackCount)
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm - 1
                            color: Theme.textFaint
                        }
                    }
                }

                onClicked: {
                    if (row.isFolder)
                        root.toggleFolder(row.modelData.id)
                    else
                        root.openPlaylist(row.modelData.id, row.modelData.title)
                }

                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onSingleTapped: (point) => {
                        const p = row.mapToItem(root, point.position.x, point.position.y)
                        if (row.isFolder)
                            root.openFolderMenu(row.modelData, p)
                        else
                            root.openPlaylistMenu(row.modelData, p)
                    }
                }
            }
        }
    }

    // Hairline against the content area.
    Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: Theme.border
    }

    ContextMenu { id: folderMenu }
    ContextMenu { id: playlistMenu }
    NamePrompt {
        id: namePrompt
        onAccepted: (text, mode, targetId) => mode === "create"
            ? writer.create_folder(text)
            : writer.rename_folder(targetId, text)
    }

    PlaylistEditDialog {
        id: editDialog
        anchors.fill: parent
        playlists: writer
        onCloseRequested: open = false
    }
}
