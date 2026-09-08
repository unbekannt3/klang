// A ContextMenu configured for one track row.
//
// `player` is not in the task's minimal prop list but is required anyway —
// Play now/Play next/Add to queue have nowhere else to go, and every page in
// this app already receives its own PlayerController rather than reaching a
// singleton (see Main.qml), so this follows the same convention.

import QtQuick
import me.unbk.klang

ContextMenu {
    id: root

    required property var track
    required property var player
    required property var favorites

    /// Opens the shared playlist picker; klang has no per-track playlist
    /// submenu data source, so this is a signal rather than a real submenu.
    signal addToPlaylistRequested(int trackId)
    /// No `TRACK_MIX` lookup exists in the bridge yet — signal only.
    signal radioRequested(int trackId)
    signal goToAlbumRequested(int albumId)
    signal goToArtistRequested(int artistId)

    // `revision` is read only so this re-evaluates when the favourite sets
    // change; `is_track` itself is a plain invokable, not a tracked property.
    readonly property bool loved: !!favorites && favorites.revision >= 0
        && favorites.is_track(track.id)

    function trackJson() {
        return JSON.stringify(track)
    }

    function buildModel() {
        if (!track)
            return []

        const items = [
            { label: "Play now", icon: "play",
              onTriggered: () => player.play_context(trackJson(), 0, "track:" + track.id) },
            { label: "Play next", icon: "next",
              onTriggered: () => player.play_next(trackJson()) },
            { label: "Add to queue", icon: "queue",
              onTriggered: () => player.enqueue(trackJson()) },
            { separator: true },
            { label: "Add to playlist", icon: "playlist",
              onTriggered: () => root.addToPlaylistRequested(track.id) },
            { label: root.loved ? "Remove from Loved Tracks" : "Add to Loved Tracks",
              icon: root.loved ? "heart-filled" : "heart",
              onTriggered: () => favorites.toggle_track(track.id) },
        ]

        // rows.rs carries only the album/artist *names*, not their ids, so
        // these only appear once a caller enriches the row with them.
        if (track.albumId)
            items.push({ label: "Go to album", onTriggered: () => root.goToAlbumRequested(track.albumId) })
        if (track.artistId)
            items.push({ label: "Go to artist", onTriggered: () => root.goToArtistRequested(track.artistId) })

        items.push({ separator: true })
        items.push({ label: "Track radio", icon: "radio",
                     onTriggered: () => root.radioRequested(track.id) })
        return items
    }

    model: buildModel()
}
