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

    WheelHandler {
        // Attach to the list itself: a visual child of a ListView lands in the
        // scrolling contentItem, where a handler's hit area moves with it.
        parent: root.view
        acceptedDevices: PointerDevice.Mouse

        onWheel: (event) => {
            if (!scroll.running)
                root.targetY = root.view.contentY

            const maxY = Math.max(0, root.view.contentHeight - root.view.height)
            const step = (event.angleDelta.y / 120) * root.rowHeight * root.rowsPerNotch
            root.targetY = Math.max(0, Math.min(maxY, root.targetY - step))

            scroll.stop()
            scroll.to = root.targetY
            scroll.start()
        }
    }

    // A drag, flick or scrollbar hands control back; resync the target.
    Connections {
        target: root.view
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
}
