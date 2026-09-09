// A ContextMenu configured for one album, artist, playlist or mix card.
//
// `item.kind` picks which actions apply. Unlike TrackContextMenu, "Play"
// has no bridge call here: an arbitrary card only carries
// {id, title, subtitle, image, kind} (see home.rs's item_row) — no track
// list to hand to the player — so it is a signal, and whichever page already
// has the full track list (album/artist/playlist detail) does the actual
// player.play_context call.

import QtQuick
import me.unbk.klang

ContextMenu {
    id: root

    required property var item
    required property var favorites

    signal playRequested(var item)
    signal goToArtistRequested(int artistId)
    // No playlist editor or delete confirmation exists yet — signals only.
    signal editRequested(string playlistId)
    signal deleteRequested(string playlistId)

    // Card rows key ids as strings (home.rs normalises everything through
    // item_id()); detail-page headers (catalog.rs) keep them numeric. Number()
    // makes both work with the FavoritesController's i64 parameters.
    function numericId() {
        return Number(item.id)
    }

    // `revision` is read only for its side effect: it makes this binding
    // re-evaluate whenever the favourite sets change.
    readonly property bool loved: {
        if (!favorites || !item)
            return false
        const _r = favorites.revision
        switch (item.kind) {
        case "album": return favorites.is_album(numericId())
        case "artist": return favorites.is_artist(numericId())
        case "playlist": return favorites.is_playlist(item.id)
        default: return false
        }
    }

    /// Only artists and videos can be blocked — albums and playlists have no
    /// blocks endpoint.
    readonly property bool blockable: !!item
        && (item.kind === "artist" || item.kind === "video")

    readonly property bool blocked: {
        if (!favorites || !root.blockable)
            return false
        const _r = favorites.revision
        return favorites.is_blocked(item.kind, numericId())
    }

    function toggleFavorite() {
        switch (item.kind) {
        case "album": favorites.toggle_album(numericId()); break
        case "artist": favorites.toggle_artist(numericId()); break
        case "playlist": favorites.toggle_playlist(item.id); break
        }
    }

    function favoriteLabel() {
        if (item.kind === "artist")
            return Tr.t(root.loved ? "Unfollow artist" : "Follow artist")
        return Tr.t(root.loved ? "Remove from library" : "Add to library")
    }

    function buildModel() {
        if (!item)
            return []

        const items = [
            { label: Tr.t("Play"), icon: "play", onTriggered: () => root.playRequested(item) },
        ]

        // Mixes have no favourite endpoint in FavoritesController at all.
        const canFavorite = item.kind === "album" || item.kind === "artist" || item.kind === "playlist"
        if (canFavorite) {
            items.push({ separator: true })
            items.push({
                label: favoriteLabel(),
                icon: root.loved ? "heart-filled" : "heart",
                onTriggered: () => toggleFavorite(),
            })
        }

        // `artistId` is only on the album-detail header row (catalog.rs); a
        // carousel/search album card does not carry it.
        if (item.kind === "album" && item.artistId)
            items.push({ label: Tr.t("Go to artist"), onTriggered: () => root.goToArtistRequested(item.artistId) })

        if (root.blockable) {
            const label = item.kind === "video"
                ? (root.blocked ? "Unblock video" : "Block video")
                : (root.blocked ? "Unblock artist" : "Block artist")
            items.push({ separator: true })
            items.push({ label: Tr.t(label), icon: "block",
                         onTriggered: () => favorites.toggle_block(item.kind, numericId()) })
        }

        if (item.kind === "playlist") {
            items.push({ separator: true })
            items.push({ label: Tr.t("Edit playlist"), onTriggered: () => root.editRequested(item.id) })
            items.push({ label: Tr.t("Delete playlist"), danger: true, onTriggered: () => root.deleteRequested(item.id) })
        }

        return items
    }

    model: buildModel()
}
