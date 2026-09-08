// Explore: the same section shape as Home, from a different TIDAL endpoint.

import QtQuick
import me.unbk.klang

Item {
    id: root

    required property var player
    /// Navigation requests bubble up to Main.qml.
    signal openAlbum(int albumId)
    signal openArtist(int artistId)
    signal openPlaylist(string uuid, string title)

    HomeController { id: home }

    Component.onCompleted: home.load_explore()

    Rectangle { anchors.fill: parent; color: Theme.base }

    SectionList {
        anchors.fill: parent
        player: root.player
        sections: home.explore_json
        loading: home.loading
        error: home.error
        emptyText: "Nothing to explore yet"
        onOpenAlbum: (id) => root.openAlbum(id)
        onOpenArtist: (id) => root.openArtist(id)
        onOpenPlaylist: (uuid, title) => root.openPlaylist(uuid, title)
    }
}
