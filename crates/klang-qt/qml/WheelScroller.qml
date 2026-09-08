// Mouse-wheel scrolling that keeps up with the hand.
//
// Flickable's own handling moves by angleDelta/8 * QStyleHints::wheelScrollLines
// — roughly 45 px per notch, less than one 56 px track row, so the list barely
// moves. This steps whole rows instead, and animates towards a target so fast
// consecutive notches compound rather than fighting each other.
//
// Touchpads are deliberately excluded: their smooth pixelDelta is already right,
// and rewriting it into discrete steps would make it stutter.

import QtQuick

Item {
    id: root

    required property var view
    /// Rows travelled per wheel notch.
    property int rowsPerNotch: 5
    property real rowHeight: 56
    /// Time to settle after the last notch. Long enough to read as motion,
    /// short enough that it never feels behind the wheel.
    property int settle: 140

    /// Where the animation is heading. Re-synced whenever the list moves by any
    /// other means — a drag, a flick, or the scrollbar.
    property real targetY: 0

    function maxY() {
        return Math.max(0, view.contentHeight - view.height)
    }

    Connections {
        target: root.view
        // Movement not driven by this handler resets the target, so the next
        // notch starts from where the list actually is.
        function onMovementStarted() {
            scroll.stop()
            root.targetY = root.view.contentY
        }
    }

    NumberAnimation {
        id: scroll
        target: root.view
        property: "contentY"
        duration: root.settle
        easing.type: Easing.OutCubic
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse
        onWheel: (event) => {
            if (!scroll.running)
                root.targetY = root.view.contentY

            // A notch is 120 units.
            const step = (event.angleDelta.y / 120) * root.rowHeight * root.rowsPerNotch
            root.targetY = Math.max(0, Math.min(root.maxY(), root.targetY - step))

            scroll.stop()
            scroll.to = root.targetY
            scroll.start()
        }
    }
}
