// Where the artist hover card is, and for whom.
//
// A singleton rather than a signal threaded up through every page: a track
// row is eight levels below the window, and the card has to sit above all of
// them. Rows call `open`, Main.qml renders the one card.

pragma Singleton

import QtQuick

QtObject {
    id: root

    property int artistId: 0
    /// Where the card should point, in window coordinates.
    property point anchor: Qt.point(0, 0)
    property bool shown: false

    /// Called on hover. The card waits out `delay` before it appears, so
    /// crossing a column does not flash one card per row.
    readonly property int delay: 550

    function open(id, windowPoint) {
        if (id <= 0)
            return
        root.artistId = id
        root.anchor = windowPoint
        root.shown = true
    }

    function close() {
        root.shown = false
    }
}
