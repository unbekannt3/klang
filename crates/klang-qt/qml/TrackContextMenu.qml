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
    // The `track.id` guard matters at startup, before any row is opened, when
    // callers seed `track` with an empty placeholder object.
    readonly property bool loved: !!favorites && !!track && !!track.id
        && favorites.revision >= 0 && favorites.is_track(track.id)

    // Blocking keeps a track out of mixes and radio; it is separate from
    // loving it, and TIDAL exposes it per track and per artist.
    readonly property bool blocked: !!favorites && !!track && !!track.id
        && favorites.revision >= 0 && favorites.is_blocked("track", track.id)
    readonly property bool artistBlocked: !!favorites && !!track && !!track.artistId
        && favorites.revision >= 0 && favorites.is_blocked("artist", track.artistId)

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

        // Only shown once the row actually carries these ids.
        if (track.albumId)
            items.push({ label: "Go to album", onTriggered: () => root.goToAlbumRequested(track.albumId) })
        if (track.artistId)
            items.push({ label: "Go to artist", onTriggered: () => root.goToArtistRequested(track.artistId) })

        items.push({ separator: true })
        items.push({ label: "Track radio", icon: "radio",
                     onTriggered: () => root.radioRequested(track.id) })

        items.push({ separator: true })
        items.push({ label: root.blocked ? "Unblock track" : "Block track", icon: "block",
                     onTriggered: () => favorites.toggle_block("track", track.id) })
        if (track.artistId)
            items.push({ label: root.artistBlocked ? "Unblock artist" : "Block artist", icon: "block",
                         onTriggered: () => favorites.toggle_block("artist", track.artistId) })
        return items
    }

    model: buildModel()
}
