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

    // Which page the content area shows.
    property string route: "favorites"

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

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Sidebar {
                Layout.fillHeight: true
                visible: auth.logged_in
                current: root.route
                playlists: playlists.playlists_json
                onNavigate: (r) => root.route = r
                onOpenPlaylist: (uuid, title) => {
                    // The playlist page lands with the playlists bridge; until
                    // then the request is recorded so nothing is silently lost.
                    console.log("open playlist", uuid, title)
                }
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

                FavoritesPage {
                    anchors.fill: parent
                    visible: auth.logged_in && root.route === "favorites"
                    player: player
                    userId: auth.user_id
                }

                // Placeholder while the home and explore bridges land.
                Item {
                    anchors.fill: parent
                    visible: auth.logged_in && root.route !== "favorites"

                    Text {
                        anchors.centerIn: parent
                        text: root.route === "home" ? "Home is being built"
                                                    : "Explore is being built"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLg
                        color: Theme.textFaint
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
