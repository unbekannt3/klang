// A slim horizontal slider. QQC2's default carries the platform style, which
// fights the TIDAL look, so this is drawn from scratch.

import QtQuick

Item {
    id: root

    property real from: 0
    property real to: 1
    /// Follows the source except while the user drags.
    property real value: 0
    property bool dragging: false

    signal seeked(real value)

    implicitHeight: 16

    readonly property real span: Math.max(to - from, 0.000001)
    readonly property real ratio: Math.max(0, Math.min(1, (value - from) / span))

    function valueAt(x) {
        const r = Math.max(0, Math.min(1, x / Math.max(width, 1)))
        return from + r * span
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        radius: height / 2
        color: Theme.sliderTrack

        Rectangle {
            width: parent.width * root.ratio
            height: parent.height
            radius: parent.radius
            color: hover.hovered || root.dragging ? Theme.accent : Theme.sliderFill
        }
    }

    Rectangle {
        visible: hover.hovered || root.dragging
        x: track.width * root.ratio - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: 12
        height: 12
        radius: width / 2
        color: Theme.textPrimary
    }

    HoverHandler { id: hover }

    TapHandler {
        onSingleTapped: (point) => root.seeked(root.valueAt(point.position.x))
    }

    DragHandler {
        id: drag
        target: null
        xAxis.enabled: true
        yAxis.enabled: false
        onActiveChanged: root.dragging = active
        onCentroidChanged: if (active) root.seeked(root.valueAt(centroid.position.x))
    }
}
