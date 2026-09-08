// Home feed: personalized carousels from TIDAL.

import QtQuick
import me.unbk.klang

Item {
    id: root

    required property var player
    /// Navigation requests bubble up to Main.qml.
    signal openAlbum(int albumId)
    signal openArtist(int artistId)
    signal openPlaylist(string uuid, string title)
    signal openMix(string mixId, string title)
    signal itemContextRequested(var item, real x, real y)
    signal openSection(var section)

    HomeController { id: home }

    Component.onCompleted: home.load_home()

    Rectangle { anchors.fill: parent; color: Theme.base }

    SectionList {
        onItemContextRequested: (item, x, y) => root.itemContextRequested(item, x, y)
        onOpenSection: (section) => root.openSection(section)
        scrollKey: "home"
        anchors.fill: parent
        player: root.player
        sections: home.sections_json
        loading: home.loading
        error: home.error
        emptyText: "Nothing to show yet"
        onOpenAlbum: (id) => root.openAlbum(id)
        onOpenArtist: (id) => root.openArtist(id)
        onOpenPlaylist: (uuid, title) => root.openPlaylist(uuid, title)
        onOpenMix: (mixId, title) => root.openMix(mixId, title)
    }
}
