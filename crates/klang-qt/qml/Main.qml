// klang — TIDAL's proportions, sone's palette.
//
// Layout follows tidal.com: a 220 px navigation rail, the content area, and a
// full-width 88 px player bar pinned to the bottom.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

QQC2.ApplicationWindow {
    id: root

    title: "klang"
    width: 1280
    height: 820
    minimumWidth: 900
    minimumHeight: 560
    visible: true
    color: Theme.base

    // Own chrome, so the titlebar carries the theme instead of Breeze. Moving
    // and resizing go through the compositor — see TitleBar and ResizeEdges.
    flags: Qt.Window | Qt.FramelessWindowHint

    // ---- navigation ----------------------------------------------------
    //
    // A page is {route, params}. `history` is the back stack; the sidebar
    // resets it, opening a detail pushes onto it.
    property var page: ({ route: "favorites", params: {} })
    property var history: []
    property bool nowPlayingOpen: false
    readonly property string route: page.route

    function go(route, params) {
        history.push(page)
        historyChanged()
        page = { route: route, params: params || {} }
    }

    /// Sidebar destinations are roots, not steps — they clear the stack.
    function goRoot(route) {
        history = []
        page = { route: route, params: {} }
    }

    function profile() {
        return JSON.parse(profileCtl.profile_json || "{}")
    }

    /// A carousel header opened in full. Sections TIDAL does not paginate
    /// carry no path, so the header is not clickable and this never fires.
    function openSection(section) {
        root.go("view-all", { apiPath: section.apiPath || "", title: section.title || "" })
    }

    /// Open the shared card menu at a point in the content area.
    function openMediaMenu(item, x, y) {
        mediaMenu.item = item
        mediaMenu.openAt(Qt.point(x, y), content)
    }

    function back() {
        if (history.length === 0)
            return
        page = history.pop()
        historyChanged()
    }

    AuthController {
        id: authCtl
        // user_id is set before logged_in, so it is already valid here.
        onLogged_inChanged: {
            if (!logged_in)
                return
            playlistsCtl.load_all(authCtl.user_id)
            favoritesCtl.load(authCtl.user_id)
            favoritesCtl.load_blocks(authCtl.user_id)
            profileCtl.load(authCtl.user_id)
        }
    }

    PlayerController { id: playerCtl }
    PlaylistsController { id: playlistsCtl }
    FavoritesController { id: favoritesCtl }
    LibraryController { id: collectionCtl }
    SettingsController { id: settingsCtl }
    ProfileController { id: profileCtl }
    SignalPathController { id: signalPathCtl }

    VideoController {
        id: videoCtl
        // A video and a track cannot both be heard at once.
        onPause_audio_requested: {
            if (playerCtl.playing)
                playerCtl.toggle()
        }
    }

    Component.onCompleted: {
        Theme.controller.restore()
        playerCtl.attach()
        settingsCtl.load()
        signalPathCtl.attach()
        authCtl.restore()
    }

    Shortcuts {
        player: playerCtl
        favorites: favoritesCtl
        settings: settingsCtl
        onSearchRequested: titleBar.focusSearch()
        onHelpRequested: shortcutsHelp.open = !shortcutsHelp.open
        // Escape closes whatever is topmost, innermost first.
        onDismissRequested: {
            if (shortcutsHelp.open)
                shortcutsHelp.open = false
            else if (signalPath.open)
                signalPath.open = false
            else if (playlistPicker.open)
                playlistPicker.open = false
            else if (root.nowPlayingOpen)
                root.nowPlayingOpen = false
        }
    }

    // ---- chrome ---------------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        TitleBar {
            id: titleBar
            Layout.fillWidth: true
            window: root
            canGoBack: root.history.length > 0
            searchQuery: root.page.params.query || ""
            avatarUrl: root.profile().avatarUrl || ""
            displayName: root.profile().name || ""
            onProfileRequested: root.go("profile", {})
            onSettingsRequested: root.goRoot("settings")
            onLogoutRequested: authCtl.logout()
            onBackRequested: root.back()
            onSearchSubmitted: (q) => {
                if (q.length === 0)
                    return
                if (root.route === "search")
                    root.page = { route: "search", params: { query: q } }
                else
                    root.go("search", { query: q })
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Sidebar {
                Layout.fillHeight: true
                visible: authCtl.logged_in
                current: root.route
                playlists: playlistsCtl.playlists_json
                onNavigate: (r) => root.goRoot(r)
                onOpenPlaylist: (uuid, title) => root.go("playlist", { uuid: uuid, title: title })
            }

            // Content area
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                LoginPage {
                    anchors.fill: parent
                    visible: !authCtl.logged_in
                    auth: authCtl
                }

                Loader {
                    id: content
                    anchors.fill: parent
                    visible: authCtl.logged_in
                    active: authCtl.logged_in

                    sourceComponent: switch (root.route) {
                        case "home":      return homePage
                        case "explore":   return exploreRootPage
                        case "search":    return searchPage
                        case "album":     return albumPage
                        case "artist":    return artistPage
                        case "playlist":  return playlistPage
                        case "settings":  return settingsPage
                        case "profile":   return profilePage
                        case "item-grid": return itemGridPage
                        case "view-all":      return viewAllPage
                        case "artist-tracks": return artistTracksPage
                        case "feed":          return feedPage
                        case "mix":           return mixPage
                        case "fav-albums":    return favAlbumsPage
                        case "fav-artists":   return favArtistsPage
                        case "fav-playlists": return favPlaylistsPage
                        default:          return favoritesPage
                    }
                }
            }
        }

        PlayerBar {
            id: bar
            Layout.fillWidth: true
            visible: playerCtl.track_id !== 0
            player: playerCtl
            favorites: favoritesCtl
            shuffle: playerCtl.shuffle
            repeat: playerCtl.repeat
            volume: playerCtl.volume
            onNextRequested: playerCtl.next()
            onPreviousRequested: playerCtl.previous()
            onShuffleToggled: playerCtl.toggle_shuffle()
            onRepeatToggled: playerCtl.toggle_repeat()
            onMuteToggled: playerCtl.toggle_mute()
            onQueueRequested: root.nowPlayingOpen = !root.nowPlayingOpen
            onExpandRequested: root.nowPlayingOpen = true
            onSignalPathRequested: signalPath.open = !signalPath.open
            onMiniPlayerRequested: miniPlayer.visible = true
        }
    }

    // One component per route. Each page bubbles navigation requests up here,
    // so no page needs to know about any other.
    Component {
        id: favoritesPage
        FavoritesPage {
            player: playerCtl
            userId: authCtl.user_id
            favorites: favoritesCtl
            onTrackContextRequested: (track, x, y) => {
                trackMenu.track = track
                trackMenu.openAt(Qt.point(x, y), content)
            }
        }
    }

    Component {
        id: homePage
        HomePage {
            player: playerCtl
            onOpenAlbum: (id) => root.go("album", { albumId: id })
            onOpenArtist: (id) => root.go("artist", { artistId: id })
            onOpenPlaylist: (uuid, title) => root.go("playlist", { uuid: uuid, title: title })
            onOpenMix: (mixId, title) => root.go("mix", { mixId: mixId, title: title })
            onItemContextRequested: (item, x, y) => root.openMediaMenu(item, x, y)
            onOpenSection: (section) => root.openSection(section)
        }
    }

    // Explore is the same page as any other category, just the root path:
    // TIDAL's own explore payload is mostly genre/mood link sections, which
    // the home carousels drop and ViewAllPage renders.
    Component {
        id: exploreRootPage
        ViewAllPage {
            player: playerCtl
            title: "Explore"
            apiPath: "pages/explore"
            sectioned: true
            userId: authCtl.user_id
            scrollKey: "explore"
            onOpenAlbum: (id) => root.go("album", { albumId: id })
            onOpenArtist: (id) => root.go("artist", { artistId: id })
            onOpenPlaylist: (uuid, title) => root.go("playlist", { uuid: uuid, title: title })
            onOpenMix: (mixId, title) => root.go("mix", { mixId: mixId, title: title })
            onOpenExplorePage: (path, title) =>
                    root.go("view-all", { apiPath: path, title: title, sectioned: true })
            onItemContextRequested: (item, x, y) => root.openMediaMenu(item, x, y)
        }
    }

    Component {
        id: searchPage
        SearchPage {
            player: playerCtl
            favorites: favoritesCtl
            onTrackContextRequested: (track, x, y) => {
                trackMenu.track = track
                trackMenu.openAt(Qt.point(x, y), content)
            }
            query: root.page.params.query || ""
            onOpenAlbum: (id) => root.go("album", { albumId: id })
            onOpenArtist: (id) => root.go("artist", { artistId: id })
            onOpenPlaylist: (uuid, title) => root.go("playlist", { uuid: uuid, title: title })
        }
    }

    Component {
        id: albumPage
        AlbumPage {
            player: playerCtl
            favorites: favoritesCtl
            onTrackContextRequested: (track, x, y) => {
                trackMenu.track = track
                trackMenu.openAt(Qt.point(x, y), content)
            }
            albumId: root.page.params.albumId || 0
            onOpenArtist: (id) => root.go("artist", { artistId: id })
        }
    }

    Component {
        id: artistPage
        ArtistPage {
            player: playerCtl
            favorites: favoritesCtl
            onTrackContextRequested: (track, x, y) => {
                trackMenu.track = track
                trackMenu.openAt(Qt.point(x, y), content)
            }
            artistId: root.page.params.artistId || 0
            onOpenAlbum: (id) => root.go("album", { albumId: id })
            onOpenArtistTracks: (artistName) => root.go("artist-tracks", {
                artistId: root.page.params.artistId || 0,
                artistName: artistName
            })
            onOpenItemGrid: (title, items) => root.go("item-grid", { title: title, items: items })
            onItemContextRequested: (item, x, y) => root.openMediaMenu(item, x, y)
        }
    }

    Component {
        id: settingsPage
        SettingsPage {}
    }

    Component {
        id: playlistPage
        PlaylistPage {
            player: playerCtl
            favorites: favoritesCtl
            onTrackContextRequested: (track, x, y) => {
                trackMenu.track = track
                trackMenu.openAt(Qt.point(x, y), content)
            }
            playlistUuid: root.page.params.uuid || ""
            playlistTitle: root.page.params.title || ""
        }
    }

    Component {
        id: viewAllPage
        ViewAllPage {
            player: playerCtl
            title: root.page.params.title || ""
            apiPath: root.page.params.apiPath || ""
            sectioned: root.page.params.sectioned || false
            viewAllPath: root.page.params.viewAllPath || ""
            artistId: root.page.params.artistId || 0
            libraryKind: root.page.params.libraryKind || ""
            userId: authCtl.user_id
            scrollKey: "view-all:" + (root.page.params.apiPath
                                      || root.page.params.libraryKind
                                      || root.page.params.viewAllPath || "")
            onOpenAlbum: (id) => root.go("album", { albumId: id })
            onOpenArtist: (id) => root.go("artist", { artistId: id })
            onOpenPlaylist: (uuid, title) => root.go("playlist", { uuid: uuid, title: title })
            onOpenMix: (mixId, title) => root.go("mix", { mixId: mixId, title: title })
            onOpenExplorePage: (path, title) =>
                    root.go("view-all", { apiPath: path, title: title, sectioned: true })
            onItemContextRequested: (item, x, y) => root.openMediaMenu(item, x, y)
        }
    }

    Component {
        id: artistTracksPage
        ArtistTracksPage {
            player: playerCtl
            favorites: favoritesCtl
            artistId: root.page.params.artistId || 0
            artistName: root.page.params.artistName || ""
            onTrackContextRequested: (track, x, y) => {
                trackMenu.track = track
                trackMenu.openAt(Qt.point(x, y), content)
            }
        }
    }

    Component {
        id: profilePage
        ProfilePage {
            controller: profileCtl
            userId: authCtl.user_id
            onOpenPlaylist: (uuid, title) => root.go("playlist", { uuid: uuid, title: title })
            onViewAllPlaylistsRequested: (playlists, name) =>
                    root.go("item-grid", { items: playlists, title: "Public playlists" })
            onBackRequested: root.back()
        }
    }

    // A carousel opened as a grid, over cards the page already holds — used
    // where TIDAL gives no "view all" endpoint to page through.
    Component {
        id: itemGridPage
        MediaGridPage {
            player: playerCtl
            title: root.page.params.title || ""
            items: root.page.params.items || []
            scrollKey: "item-grid:" + (root.page.params.title || "")
            onOpenAlbum: (id) => root.go("album", { albumId: id })
            onOpenArtist: (id) => root.go("artist", { artistId: id })
            onOpenPlaylist: (uuid, title) => root.go("playlist", { uuid: uuid, title: title })
            onOpenMix: (mixId, title) => root.go("mix", { mixId: mixId, title: title })
            onItemContextRequested: (item, x, y) => root.openMediaMenu(item, x, y)
        }
    }

    Component {
        id: feedPage
        FeedPage {
            player: playerCtl
            userId: authCtl.user_id
            onOpenAlbum: (id) => root.go("album", { albumId: id })
            onOpenArtist: (id) => root.go("artist", { artistId: id })
            onOpenPlaylist: (uuid, title) => root.go("playlist", { uuid: uuid, title: title })
        }
    }

    Component {
        id: mixPage
        MixPage {
            player: playerCtl
            mixId: root.page.params.mixId || ""
            mixTitle: root.page.params.title || ""
            mixItems: mixCtl.tracks_json
            loading: mixCtl.loading
            error: mixCtl.error
            onOpenAlbum: (id) => root.go("album", { albumId: id })
            onOpenArtist: (id) => root.go("artist", { artistId: id })
            Component.onCompleted: mixCtl.load(mixId)
        }
    }

    // The three collection grids differ only in their source and heading.
    // The three library grids differ only in which favourites they page
    // through; ViewAllPage handles the paging and the sort control.
    component CollectionGrid: ViewAllPage {
        player: playerCtl
        userId: authCtl.user_id
        onOpenAlbum: (id) => root.go("album", { albumId: id })
        onOpenArtist: (id) => root.go("artist", { artistId: id })
        onOpenPlaylist: (uuid, title) => root.go("playlist", { uuid: uuid, title: title })
        onOpenMix: (mixId, title) => root.go("mix", { mixId: mixId, title: title })
        onItemContextRequested: (item, x, y) => root.openMediaMenu(item, x, y)
    }

    Component {
        id: favAlbumsPage
        CollectionGrid {
            title: "Albums"
            libraryKind: "albums"
            scrollKey: "fav-albums"
        }
    }

    Component {
        id: favArtistsPage
        CollectionGrid {
            title: "Artists"
            libraryKind: "artists"
            scrollKey: "fav-artists"
        }
    }

    Component {
        id: favPlaylistsPage
        CollectionGrid {
            title: "Playlists"
            libraryKind: "playlists"
            scrollKey: "fav-playlists"
        }
    }

    MixController { id: mixCtl }

    TrackContextMenu {
        id: trackMenu
        property int rowIndex: -1
        track: ({})
        player: playerCtl
        favorites: favoritesCtl
        onAddToPlaylistRequested: (trackId) => {
            playlistPicker.trackId = trackId
            playlistPicker.open = true
        }
        onGoToAlbumRequested: (albumId) => root.go("album", { albumId: albumId })
        onGoToArtistRequested: (artistId) => root.go("artist", { artistId: artistId })
        onRadioRequested: (trackId) => console.log("track radio not wired yet", trackId)
    }

    MediaContextMenu {
        id: mediaMenu
        item: ({})
        favorites: favoritesCtl
        onPlayRequested: (item) => {
            if (item.kind === "album")
                root.go("album", { albumId: parseInt(item.id) })
            else if (item.kind === "playlist")
                root.go("playlist", { uuid: item.id, title: item.title })
            else if (item.kind === "mix")
                root.go("mix", { mixId: item.id, title: item.title })
            else if (item.kind === "artist")
                root.go("artist", { artistId: parseInt(item.id) })
        }
        onGoToArtistRequested: (artistId) => root.go("artist", { artistId: artistId })
        onEditRequested: (playlistId) => root.go("playlist", { uuid: playlistId, title: "" })
        onDeleteRequested: (playlistId) => playlistsCtl.remove(playlistId)
    }

    AddToPlaylistDialog {
        id: playlistPicker
        anchors.fill: parent
        playlists: playlistsCtl
        onCloseRequested: open = false
    }

    ShortcutsHelp {
        id: shortcutsHelp
        anchors.fill: parent
        onCloseRequested: shortcutsHelp.open = false
    }

    SignalPathPanel {
        id: signalPath
        anchors.fill: parent
        player: playerCtl
        path: signalPathCtl
        onCloseRequested: signalPath.open = false
    }

    VideoPlayerView {
        anchors.fill: parent
        controller: videoCtl
        userId: authCtl.user_id
        onMinimizeRequested: videoCtl.close()
    }

    MiniPlayerWindow {
        id: miniPlayer
        visible: false
        player: playerCtl
        favorites: favoritesCtl
    }

    NowPlayingView {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        // The player bar lives in the layout, so it cannot be anchored to.
        height: parent.height - (bar.visible ? bar.height : 0)
        player: playerCtl
        open: root.nowPlayingOpen
        onCloseRequested: root.nowPlayingOpen = false
    }

    ResizeEdges {
        window: root
    }

    // Playback errors are shown in place rather than stealing focus mid-track.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.playerBarHeight + Theme.space
        width: Math.min(errorText.implicitWidth + Theme.spaceXl, root.width - Theme.spaceXl)
        height: errorText.implicitHeight + Theme.space
        radius: Theme.radius
        color: Theme.elevated
        border.color: Theme.error
        border.width: 1
        opacity: playerCtl.error.length > 0 ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.duration }
        }

        Text {
            id: errorText
            anchors.centerIn: parent
            width: parent.width - Theme.space
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: playerCtl.error
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textPrimary
        }

        Timer {
            id: errorTimer
            interval: 6000
            onTriggered: playerCtl.error = ""
        }

        Connections {
            target: playerCtl
            function onErrorChanged() {
                if (playerCtl.error.length > 0)
                    errorTimer.restart()
            }
        }
    }
}
