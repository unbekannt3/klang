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
    property bool queueOpen: false
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

    function back() {
        if (history.length === 0)
            return
        page = history.pop()
        historyChanged()
    }

    AuthController {
        id: authCtl
        // user_id is set before logged_in, so it is already valid here.
        onLogged_inChanged: if (logged_in) playlistsCtl.load_all(authCtl.user_id)
    }

    PlayerController { id: playerCtl }
    PlaylistsController { id: playlistsCtl }

    Component.onCompleted: {
        Theme.controller.restore()
        playerCtl.attach()
        authCtl.restore()
    }

    // ---- chrome ---------------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        TitleBar {
            Layout.fillWidth: true
            window: root
            canGoBack: root.history.length > 0
            searchQuery: root.page.params.query || ""
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
                        case "explore":   return explorePage
                        case "search":    return searchPage
                        case "album":     return albumPage
                        case "artist":    return artistPage
                        case "playlist":  return playlistPage
                        case "settings":  return settingsPage
                        default:          return favoritesPage
                    }
                }
            }
        }

        PlayerBar {
            Layout.fillWidth: true
            visible: playerCtl.track_id !== 0
            player: playerCtl
            shuffle: playerCtl.shuffle
            repeat: playerCtl.repeat
            volume: playerCtl.volume
            onNextRequested: playerCtl.next()
            onPreviousRequested: playerCtl.previous()
            onShuffleToggled: playerCtl.toggle_shuffle()
            onRepeatToggled: playerCtl.toggle_repeat()
            onMuteToggled: playerCtl.toggle_mute()
            onQueueRequested: root.queueOpen = !root.queueOpen
        }
    }

    // One component per route. Each page bubbles navigation requests up here,
    // so no page needs to know about any other.
    Component {
        id: favoritesPage
        FavoritesPage { player: playerCtl; userId: authCtl.user_id }
    }

    Component {
        id: homePage
        HomePage {
            player: playerCtl
            onOpenAlbum: (id) => root.go("album", { albumId: id })
            onOpenArtist: (id) => root.go("artist", { artistId: id })
            onOpenPlaylist: (uuid, title) => root.go("playlist", { uuid: uuid, title: title })
        }
    }

    Component {
        id: explorePage
        ExplorePage {
            player: playerCtl
            onOpenAlbum: (id) => root.go("album", { albumId: id })
            onOpenArtist: (id) => root.go("artist", { artistId: id })
            onOpenPlaylist: (uuid, title) => root.go("playlist", { uuid: uuid, title: title })
        }
    }

    Component {
        id: searchPage
        SearchPage {
            player: playerCtl
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
            albumId: root.page.params.albumId || 0
            onOpenArtist: (id) => root.go("artist", { artistId: id })
        }
    }

    Component {
        id: artistPage
        ArtistPage {
            player: playerCtl
            artistId: root.page.params.artistId || 0
            onOpenAlbum: (id) => root.go("album", { albumId: id })
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
            playlistUuid: root.page.params.uuid || ""
            playlistTitle: root.page.params.title || ""
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
