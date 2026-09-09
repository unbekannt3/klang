// Where a media card goes when it is activated. One table, because the four
// callers — the home/explore carousels, the favourite grids, the feed and the
// window's own card menu — must agree on it: a "mix" that opened the playlist
// page in one of them was a live bug.
pragma Singleton

import QtQuick

QtObject {
    /// Dispatches `item` on its `kind`. `on` carries one callback per
    /// destination, each taking the arguments that page needs.
    ///
    /// `on.play` is the fallback for kinds with no page of their own: TIDAL's
    /// own feeds label anything they do not recognise a track (see item_kind
    /// in home.rs). Callers that only navigate leave it out.
    function open(item, on) {
        switch (item.kind) {
        case "album":
            return on.album(parseInt(item.id))
        case "artist":
            return on.artist(parseInt(item.id))
        case "playlist":
            return on.playlist(item.id, item.title)
        case "mix":
            return on.mix(item.id, item.title)
        default:
            return on.play ? on.play(item) : undefined
        }
    }
}
