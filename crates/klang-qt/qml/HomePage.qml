// Home page — stub. See the page contract in Main.qml's Router.

import QtQuick
import me.unbk.klang

Item {
    id: root

    required property var player
    /// Navigation requests bubble up to Main.qml.
    signal openAlbum(int albumId)
    signal openArtist(int artistId)
    signal openPlaylist(string uuid, string title)

    Rectangle { anchors.fill: parent; color: Theme.base }

    Text {
        anchors.centerIn: parent
        text: "Home — not built yet"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeLg
        color: Theme.textFaint
    }
}
