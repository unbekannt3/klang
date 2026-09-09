// How many overlays currently cover the page area.
//
// Qt Quick delivers a press to every handler under the cursor until one takes
// an exclusive grab, so an overlay drawn on top does not by itself stop the
// page beneath from reacting. Rather than each overlay inventing its own
// guard, every one of them puts a ModalShield with `blocksPage` at its base
// and the page area binds `enabled` to `covered`.

pragma Singleton

import QtQuick

QtObject {
    id: root

    property int depth: 0
    readonly property bool covered: root.depth > 0

    function push() { root.depth += 1 }
    function pop() { root.depth = Math.max(0, root.depth - 1) }
}
