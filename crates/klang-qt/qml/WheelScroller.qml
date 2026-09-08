// Sane mouse-wheel steps for a ListView.
//
// Flickable moves by angleDelta/8 * QStyleHints::wheelScrollLines — roughly
// 45 px per notch, which is less than one 56 px track row and feels stuck.
// This scrolls by whole rows instead. Touchpads are left alone: their smooth
// pixelDelta is already right, and rewriting it would make it jump.

import QtQuick

WheelHandler {
    id: root

    required property var view
    /// Rows per wheel notch.
    property int rowsPerNotch: 3
    property real rowHeight: 56

    acceptedDevices: PointerDevice.Mouse
    // A notch is 120 units; trackpads send smaller deltas but are excluded above.
    onWheel: (event) => {
        const notches = event.angleDelta.y / 120
        const step = notches * root.rowHeight * root.rowsPerNotch
        const maxY = Math.max(0, view.contentHeight - view.height)
        view.contentY = Math.max(0, Math.min(maxY, view.contentY - step))
    }
}
