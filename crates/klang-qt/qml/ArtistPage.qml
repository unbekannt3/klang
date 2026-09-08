// Artist page — stub. See the page contract in Main.qml's Router.

import QtQuick
import me.unbk.klang

Item {
    id: root

    required property var player
    /// Artist to display.
    property int artistId: 0
    /// Navigation requests bubble up to Main.qml.
    signal openAlbum(int albumId)
    signal openArtist(int artistId)
    signal openPlaylist(string uuid, string title)

    Rectangle { anchors.fill: parent; color: Theme.base }

    Text {
        anchors.centerIn: parent
        text: "Artist — not built yet"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeLg
        color: Theme.textFaint
    }
}
