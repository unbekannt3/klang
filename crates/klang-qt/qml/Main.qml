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
    readonly property string route: page.route

    // Overlays are built on first open rather than at startup, so their open
    // state has to outlive them — a Loader destroys its item.
    property bool nowPlayingOpen: false
    property bool shortcutsOpen: false
    property bool signalPathOpen: false
    property bool playlistPickerOpen: false
    property int playlistPickerTrack: 0
    /// Trails `nowPlayingOpen` so the panel can finish sliding out.
    property bool nowPlayingLive: false

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

    readonly property var profile: JSON.parse(profileCtl.profile_json || "{}")

    /// A carousel header opened in full. Sections TIDAL does not paginate
    /// carry no path, so the header is not clickable and this never fires.
    function openSection(section) {
        root.go("view-all", { apiPath: section.apiPath || "", title: section.title || "" })
    }

    /// Hand a video to the takeover player. Videos are not tracks and never
    /// enter the audio queue; VideoController pauses the audio itself.
    function playVideo(videoId) {
        videoCtl.load_video(videoId, "HIGH", authCtl.user_id)
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

    // The translation table is a singleton, so the saved language reaches it
    // through a binding rather than through every page.
    Binding {
        target: Tr
        property: "language"
        value: settingsCtl.language
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
        onHelpRequested: root.shortcutsOpen = !root.shortcutsOpen
        // Escape closes whatever is topmost, innermost first.
        onDismissRequested: {
            if (root.shortcutsOpen)
                root.shortcutsOpen = false
            else if (root.signalPathOpen)
                root.signalPathOpen = false
            else if (root.playlistPickerOpen)
                root.playlistPickerOpen = false
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
            avatarUrl: root.profile.avatarUrl || ""
            displayName: root.profile.name || ""
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
                        case "fav-videos":    return favVideosPage
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
            onSignalPathRequested: root.signalPathOpen = !root.signalPathOpen
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
            favorites: favoritesCtl
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
            favorites: favoritesCtl
            title: Tr.t("Explore")
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
            onOpenSection: (section) => root.openSection(section)
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
            onOpenVideo: (id) => root.playVideo(id)
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
            favorites: favoritesCtl
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
            onOpenSection: (section) => root.openSection(section)
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
                    root.go("item-grid", { items: playlists, title: Tr.t("Public playlists") })
            onBackRequested: root.back()
        }
    }

    // A carousel opened as a grid, over cards the page already holds — used
    // where TIDAL gives no "view all" endpoint to page through.
    Component {
        id: itemGridPage
        MediaGridPage {
            player: playerCtl
            favorites: favoritesCtl
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
            onOpenMix: (mixId, title) => root.go("mix", { mixId: mixId, title: title })
        }
    }

    Component {
        id: mixPage
        MixPage {
            player: playerCtl
            favorites: favoritesCtl
            onTrackContextRequested: (track, x, y) => {
                trackMenu.track = track
                trackMenu.openAt(Qt.point(x, y), content)
            }
            mixId: root.page.params.mixId || ""
            mixTitle: root.page.params.title || ""
            // The mix's own cover once it has loaded, the cover the caller
            // seeded before that.
            mixImage: mixCtl.image || root.page.params.image || ""
            mixItems: mixCtl.tracks_json
            loading: mixCtl.loading
            error: mixCtl.error
            onOpenAlbum: (id) => root.go("album", { albumId: id })
            onOpenArtist: (id) => root.go("artist", { artistId: id })
            // Track radio arrives with only the track: rows outside a track
            // detail response carry no mix id, so the page opens first and
            // the controller looks the mix up.
            Component.onCompleted: {
                if (mixId)
                    mixCtl.load(mixId)
                else
                    mixCtl.load_track_radio(root.page.params.trackId || 0)
            }
        }
    }

    // The three collection grids differ only in their source and heading.
    // The three library grids differ only in which favourites they page
    // through; ViewAllPage handles the paging and the sort control.
    component CollectionGrid: ViewAllPage {
        player: playerCtl
        favorites: favoritesCtl
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
            title: Tr.t("Albums")
            libraryKind: "albums"
            scrollKey: "fav-albums"
        }
    }

    Component {
        id: favArtistsPage
        CollectionGrid {
            title: Tr.t("Artists")
            libraryKind: "artists"
            scrollKey: "fav-artists"
        }
    }

    Component {
        id: favPlaylistsPage
        CollectionGrid {
            title: Tr.t("Playlists")
            libraryKind: "playlists"
            scrollKey: "fav-playlists"
        }
    }

    MixController { id: mixCtl }

    // Videos are the one collection ViewAllPage cannot serve: TIDAL's
    // favourite-videos endpoint reports no total, so there is nothing to
    // paginate against — LibraryController reads the whole list instead.
    Component {
        id: favVideosPage

        MediaGridPage {
            player: playerCtl
            favorites: favoritesCtl
            title: Tr.t("Videos")
            scrollKey: "fav-videos"
            items: videoLibrary.videos_json
            loading: videoLibrary.loading
            error: videoLibrary.error
            onOpenVideo: (id) => root.playVideo(id)
            onItemContextRequested: (item, x, y) => root.openMediaMenu(item, x, y)

            LibraryController { id: videoLibrary }

            Component.onCompleted: if (authCtl.user_id !== 0)
                videoLibrary.load_videos(authCtl.user_id)
        }
    }

    TrackContextMenu {
        id: trackMenu
        property int rowIndex: -1
        track: ({})
        player: playerCtl
        favorites: favoritesCtl
        onAddToPlaylistRequested: (trackId) => {
            root.playlistPickerTrack = trackId
            root.playlistPickerOpen = true
        }
        onGoToAlbumRequested: (albumId) => root.go("album", { albumId: albumId })
        onGoToArtistRequested: (artistId) => root.go("artist", { artistId: artistId })
        onRadioRequested: (trackId) => root.go("mix", {
            mixId: trackMenu.track.trackMix || "",
            trackId: trackId,
            title: Tr.t("%1 Radio").arg(trackMenu.track.title || ""),
            image: trackMenu.track.cover || "",
        })
    }

    MediaContextMenu {
        id: mediaMenu
        item: ({})
        favorites: favoritesCtl
        onPlayRequested: (item) => MediaRoute.open(item, {
            album: (id) => root.go("album", { albumId: id }),
            artist: (id) => root.go("artist", { artistId: id }),
            playlist: (uuid, title) => root.go("playlist", { uuid: uuid, title: title }),
            mix: (mixId, title) => root.go("mix", { mixId: mixId, title: title }),
        })
        onGoToArtistRequested: (artistId) => root.go("artist", { artistId: artistId })
        onEditRequested: (playlistId) => root.go("playlist", { uuid: playlistId, title: "" })
        onDeleteRequested: (playlistId) => playlistsCtl.remove(playlistId)
    }

    // ---- overlays -------------------------------------------------------
    //
    // Each is built the first time it is opened. Built eagerly they cost real
    // work for nothing: the picker pulls a cover per playlist, the video view
    // allocates a QtMultimedia pipeline, and the now-playing panel holds a row
    // and a cover fetch per queue entry.

    Loader {
        anchors.fill: parent
        active: root.playlistPickerOpen

        sourceComponent: AddToPlaylistDialog {
            playlists: playlistsCtl
            trackId: root.playlistPickerTrack
            open: true
            onCloseRequested: root.playlistPickerOpen = false
        }
    }

    Loader {
        anchors.fill: parent
        active: root.shortcutsOpen

        sourceComponent: ShortcutsHelp {
            open: true
            onCloseRequested: root.shortcutsOpen = false
        }
    }

    Loader {
        anchors.fill: parent
        active: root.signalPathOpen

        sourceComponent: SignalPathPanel {
            player: playerCtl
            path: signalPathCtl
            open: true
            onCloseRequested: root.signalPathOpen = false
        }
    }

    Loader {
        anchors.fill: parent
        // Sit above everything else, including the player bar.
        z: 1000
        active: videoCtl.video_id !== 0

        sourceComponent: VideoPlayerView {
            controller: videoCtl
            userId: authCtl.user_id
            onMinimizeRequested: videoCtl.close()
        }
    }

    MiniPlayerWindow {
        id: miniPlayer
        visible: false
        player: playerCtl
        favorites: favoritesCtl
    }

    // The panel slides out on close, so it has to outlive `nowPlayingOpen` by
    // the length of that animation before the Loader takes it away.
    onNowPlayingOpenChanged: {
        if (root.nowPlayingOpen) {
            nowPlayingRetire.stop()
            root.nowPlayingLive = true
        } else {
            nowPlayingRetire.restart()
        }
    }

    Timer {
        id: nowPlayingRetire
        interval: Theme.duration + 50
        onTriggered: root.nowPlayingLive = false
    }

    Loader {
        anchors.left: parent.left
        anchors.right: parent.right
        // Below the titlebar, not over it: the panel's own close glyph would
        // otherwise sit on the window's close button, and a tap that misses
        // the panel by a pixel quits the app. Both bars live in the layout,
        // so their heights are read rather than anchored to.
        y: titleBar.height
        height: parent.height - titleBar.height - (bar.visible ? bar.height : 0)
        active: root.nowPlayingLive

        // Bound after creation: as an initial value `open` would already be
        // true on the first frame and the slide-in would never be seen.
        onLoaded: item.open = Qt.binding(() => root.nowPlayingOpen)

        sourceComponent: NowPlayingView {
            player: playerCtl
            favorites: favoritesCtl
            onCloseRequested: root.nowPlayingOpen = false
            onTrackContextRequested: (track, x, y) => {
                trackMenu.track = track
                trackMenu.openAt(Qt.point(x, y), content)
            }
        }
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
