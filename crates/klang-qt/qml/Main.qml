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
        id: auth
        // user_id is set before logged_in, so it is already valid here.
        onLogged_inChanged: if (logged_in) playlists.load_all(auth.user_id)
    }

    PlayerController { id: player }
    PlaylistsController { id: playlists }

    Component.onCompleted: {
        player.attach()
        auth.restore()
    }

    // ---- chrome ---------------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        TitleBar {
            Layout.fillWidth: true
            window: root
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Sidebar {
                Layout.fillHeight: true
                visible: auth.logged_in
                current: root.route
                playlists: playlists.playlists_json
                onNavigate: (r) => root.goRoot(r)
                onOpenPlaylist: (uuid, title) => root.go("playlist", { uuid: uuid, title: title })
            }

            // Content area
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                LoginPage {
                    anchors.fill: parent
                    visible: !auth.logged_in
                    auth: auth
                }

                Loader {
                    id: content
                    anchors.fill: parent
                    visible: auth.logged_in
                    active: auth.logged_in

                    sourceComponent: switch (root.route) {
                        case "home":      return homePage
                        case "explore":   return explorePage
                        case "search":    return searchPage
                        case "album":     return albumPage
                        case "artist":    return artistPage
                        case "playlist":  return playlistPage
                        default:          return favoritesPage
                    }
                }
            }
        }

        PlayerBar {
            Layout.fillWidth: true
            visible: player.track_id !== 0
            player: player
        }
    }

    // One component per route. Each page bubbles navigation requests up here,
    // so no page needs to know about any other.
    Component {
        id: favoritesPage
        FavoritesPage { player: player; userId: auth.user_id }
    }

    Component {
        id: homePage
        HomePage {
            player: player
            onOpenAlbum: (id) => root.go("album", { albumId: id })
            onOpenArtist: (id) => root.go("artist", { artistId: id })
            onOpenPlaylist: (uuid, title) => root.go("playlist", { uuid: uuid, title: title })
        }
    }

    Component {
        id: explorePage
        ExplorePage {
            player: player
            onOpenAlbum: (id) => root.go("album", { albumId: id })
            onOpenArtist: (id) => root.go("artist", { artistId: id })
            onOpenPlaylist: (uuid, title) => root.go("playlist", { uuid: uuid, title: title })
        }
    }

    Component {
        id: searchPage
        SearchPage {
            player: player
            query: root.page.params.query || ""
            onOpenAlbum: (id) => root.go("album", { albumId: id })
            onOpenArtist: (id) => root.go("artist", { artistId: id })
            onOpenPlaylist: (uuid, title) => root.go("playlist", { uuid: uuid, title: title })
        }
    }

    Component {
        id: albumPage
        AlbumPage {
            player: player
            albumId: root.page.params.albumId || 0
            onOpenArtist: (id) => root.go("artist", { artistId: id })
        }
    }

    Component {
        id: artistPage
        ArtistPage {
            player: player
            artistId: root.page.params.artistId || 0
            onOpenAlbum: (id) => root.go("album", { albumId: id })
        }
    }

    Component {
        id: playlistPage
        PlaylistPage {
            player: player
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
        opacity: player.error.length > 0 ? 1 : 0
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
            text: player.error
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textPrimary
        }

        Timer {
            id: errorTimer
            interval: 6000
            onTriggered: player.error = ""
        }

        Connections {
            target: player
            function onErrorChanged() {
                if (player.error.length > 0)
                    errorTimer.restart()
            }
        }
    }
}
