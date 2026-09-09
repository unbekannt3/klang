// The generic "everything in this section" page — tidal.com's "View all"
// destination. Four callers, three shapes:
//
//   - apiPath alone:                 flatten a section into one grid.
//   - artistId + viewAllPath:        an artist sub-page's paginated grid.
//   - libraryKind + userId:          library favourites, paginated, sortable.
//   - apiPath + sectioned:           an Explore category — carousels, or a
//                                    genre/mood/decade link grid.
//
// The first three are all a grid of MediaCards, so they share MediaGridPage;
// the fourth reuses SectionList for its carousels and a small link grid of
// its own for the nav-link case.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    required property var player
    property var favorites: null
    property string title: ""

    /// Loaded once, no pagination — a home/library section's "View all".
    property string apiPath: ""
    /// True for an Explore category: renders `sections_json`/`nav_items_json`
    /// instead of flattening `apiPath` into one grid.
    property bool sectioned: false

    /// Paginated "view all" from an artist sub-page; requires artistId.
    property string viewAllPath: ""
    property int artistId: 0

    /// Library favourites; one of "albums", "artists", "playlists", "mixes".
    property string libraryKind: ""
    property int userId: 0

    property string scrollKey: ""

    signal openAlbum(int albumId)
    signal openArtist(int artistId)
    signal openPlaylist(string uuid, string title)
    signal openMix(string mixId, string title)
    signal openVideo(int videoId)
    /// A genre/mood/decade link was activated (Explore link-grid mode).
    signal openExplorePage(string apiPath, string title)
    signal itemContextRequested(var item, real x, real y)
    /// A carousel inside a category, opened in full. Unlike a category, the
    /// result is one flat grid rather than more carousels.
    signal openSection(var section)

    readonly property bool libraryMode: root.libraryKind.length > 0
    readonly property bool artistViewAllMode: root.artistId > 0 && root.viewAllPath.length > 0
    readonly property bool exploreMode: root.sectioned && !libraryMode && !artistViewAllMode
    readonly property bool gridMode: !exploreMode
    readonly property bool sortable: libraryMode
    /// A minimal, honest subset of `SortDropdown`'s per-kind options — the
    /// two that apply to every library kind we fetch.
    property string sortOrder: "DATE"
    property string sortDirection: "DESC"

    /// Typical width of a genre/mood link label; no Theme token covers a
    /// link-grid column, so this is a local constant like ArtistPage's
    /// `avatarSize`.
    readonly property int navColumnWidth: 220

    ViewAllController { id: viewAll }

    function reload() {
        if (root.libraryMode)
            viewAll.load_library(root.libraryKind, root.userId)
        else if (root.artistViewAllMode)
            viewAll.load_artist_view_all(root.artistId, root.viewAllPath)
        else if (root.exploreMode)
            viewAll.load_explore_section(root.apiPath)
        else if (root.apiPath.length > 0)
            viewAll.load_section(root.apiPath)
    }

    function navRows() {
        return JSON.parse(viewAll.nav_items_json || "[]")
    }

    function toggleSort() {
        if (root.sortOrder === "DATE") {
            root.sortOrder = "NAME"
            root.sortDirection = "ASC"
        } else {
            root.sortOrder = "DATE"
            root.sortDirection = "DESC"
        }
        viewAll.set_library_sort(root.sortOrder, root.sortDirection)
    }

    function loadMore() {
        if (root.libraryMode)
            viewAll.load_more_library()
        else if (root.artistViewAllMode)
            viewAll.load_more_view_all()
    }

    // A page is configured one property at a time, so several of these fire
    // while it is being built. Each reload clears and refetches, and three
    // concurrent fetches all append their page — the list came out tripled.
    // Collapsing them into one call at the end of the frame fixes that.
    Timer {
        id: reloadDebounce
        interval: 0
        onTriggered: root.reload()
    }

    onApiPathChanged: reloadDebounce.restart()
    onArtistIdChanged: reloadDebounce.restart()
    onViewAllPathChanged: reloadDebounce.restart()
    onLibraryKindChanged: reloadDebounce.restart()
    onUserIdChanged: reloadDebounce.restart()
    Component.onCompleted: reloadDebounce.restart()

    Rectangle {
        anchors.fill: parent
        color: Theme.base
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spaceLg
            Layout.rightMargin: Theme.spaceLg
            Layout.topMargin: Theme.spaceLg
            Layout.bottomMargin: Theme.space
            visible: root.title.length > 0
            spacing: Theme.space

            Text {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeDisplay
                font.weight: Font.Bold
                color: Theme.textPrimary
            }

            Text {
                visible: root.libraryMode && viewAll.total > 0
                text: Tr.t(viewAll.total === 1 ? "%1 item" : "%1 items").arg(viewAll.total)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textMuted
            }

            Rectangle {
                visible: root.sortable
                implicitWidth: sortLabel.implicitWidth + Theme.space
                implicitHeight: 30
                radius: Theme.radiusFull
                color: sortHover.hovered ? Theme.hlFaint : Theme.inset
                border.color: Theme.border
                border.width: 1

                HoverHandler { id: sortHover }
                TapHandler { onSingleTapped: root.toggleSort() }

                Text {
                    id: sortLabel
                    anchors.centerIn: parent
                    text: Tr.t(root.sortOrder === "NAME" ? "Name" : "Recently added")
                          + (root.sortDirection === "ASC" ? " ↑" : " ↓")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    font.weight: Font.DemiBold
                    color: Theme.textPrimary
                }
            }
        }

        MediaGridPage {
            favorites: root.favorites
            visible: root.gridMode
            Layout.fillWidth: true
            Layout.fillHeight: true
            player: root.player
            items: viewAll.items_json
            loading: viewAll.loading
            error: viewAll.error
            scrollKey: root.scrollKey
            onOpenAlbum: (id) => root.openAlbum(id)
            onOpenArtist: (id) => root.openArtist(id)
            onOpenPlaylist: (uuid, t) => root.openPlaylist(uuid, t)
            onOpenMix: (mixId, t) => root.openMix(mixId, t)
            onOpenVideo: (id) => root.openVideo(id)
            onItemContextRequested: (item, x, y) => root.itemContextRequested(item, x, y)
        }

        // "Load more" for the two paginated grid modes — plain apiPath grids
        // never set `has_more`, so this stays hidden for those.
        Rectangle {
            visible: root.gridMode && viewAll.has_more
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: Theme.spaceLg
            opacity: viewAll.loading ? 0.5 : 1
            implicitWidth: loadMoreLabel.implicitWidth + Theme.spaceLg
            implicitHeight: 38
            radius: Theme.radiusFull
            color: loadMoreHover.hovered ? Theme.hlFaint : Theme.inset
            border.color: Theme.border
            border.width: 1

            HoverHandler { id: loadMoreHover }
            TapHandler {
                enabled: !viewAll.loading
                onSingleTapped: root.loadMore()
            }

            Text {
                id: loadMoreLabel
                anchors.centerIn: parent
                text: Tr.t("Show more")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.weight: Font.DemiBold
                color: Theme.textPrimary
            }
        }

        Item {
            visible: root.exploreMode
            Layout.fillWidth: true
            Layout.fillHeight: true

            SectionList {
                favorites: root.favorites
                visible: !viewAll.is_nav_section
                anchors.fill: parent
                player: root.player
                sections: viewAll.sections_json
                loading: viewAll.loading
                error: viewAll.error
                scrollKey: root.scrollKey
                emptyText: Tr.t("Nothing to show yet")
                onOpenSection: (section) => root.openSection(section)
                onOpenAlbum: (id) => root.openAlbum(id)
                onOpenArtist: (id) => root.openArtist(id)
                onOpenPlaylist: (uuid, t) => root.openPlaylist(uuid, t)
                onOpenMix: (mixId, t) => root.openMix(mixId, t)
                onOpenVideo: (id) => root.openVideo(id)
            }

            GridView {
                id: navGrid
                visible: viewAll.is_nav_section
                anchors.fill: parent
                anchors.margins: Theme.spaceLg
                clip: true
                model: root.navRows()
                reuseItems: true

                readonly property int columns: Math.max(1, Math.floor(width / root.navColumnWidth))
                cellWidth: width / columns
                cellHeight: 40

                HoverHandler { id: navGridHover }

                WheelScroller {
                    view: navGrid
                    rowHeight: navGrid.cellHeight
                }

                QQC2.ScrollBar.vertical: ThemedScrollBar {
                    listHovered: navGridHover.hovered
                }

                delegate: Item {
                    id: navCell
                    required property var modelData
                    width: navGrid.cellWidth
                    height: navGrid.cellHeight

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spaceLg
                        anchors.verticalCenter: parent.verticalCenter
                        text: navCell.modelData.title || ""
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLg
                        font.weight: Font.DemiBold
                        color: navHover.hovered ? Theme.textPrimary : Theme.textSecondary
                    }

                    HoverHandler { id: navHover }
                    TapHandler {
                        onSingleTapped: root.openExplorePage(navCell.modelData.apiPath, navCell.modelData.title)
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: viewAll.is_nav_section && navGrid.count === 0 && !viewAll.loading
                text: viewAll.error.length > 0 ? viewAll.error : Tr.t("Nothing here")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLg
                color: Theme.textFaint
            }

            QQC2.BusyIndicator {
                anchors.centerIn: parent
                visible: viewAll.is_nav_section
                running: viewAll.loading
            }
        }
    }
}
