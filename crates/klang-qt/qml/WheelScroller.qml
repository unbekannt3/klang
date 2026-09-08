// Flickable moves ~45 px per notch, less than one track row. Steps whole rows
// instead, animated so consecutive notches compound. Touchpads keep Flickable's
// smooth pixelDelta.

import QtQuick

Item {
    id: root

    required property var view
    property int rowsPerNotch: 5
    property real rowHeight: 56
    property int settle: 140
    property real targetY: 0

    function maxY() {
        return Math.max(0, view.contentHeight - view.height)
    }

    Connections {
        target: root.view
        // A drag, flick or scrollbar hands control back; resync the target.
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

            const step = (event.angleDelta.y / 120) * root.rowHeight * root.rowsPerNotch
            root.targetY = Math.max(0, Math.min(root.maxY(), root.targetY - step))

            scroll.stop()
            scroll.to = root.targetY
            scroll.start()
        }
    }
}
