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

    /// False while the length is unknown — `to` still sits at `from`. The
    /// fill then stays empty rather than dividing by a stand-in span and
    /// landing at 100%, which reads as a track played to the end.
    readonly property bool measured: root.to > root.from
    readonly property real span: root.measured ? root.to - root.from : 1
    readonly property real ratio: root.measured
        ? Math.max(0, Math.min(1, (root.value - root.from) / root.span))
        : 0

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
        enabled: root.measured
        onSingleTapped: (point) => root.seeked(root.valueAt(point.position.x))
    }

    DragHandler {
        id: drag
        enabled: root.measured
        target: null
        xAxis.enabled: true
        yAxis.enabled: false
        onActiveChanged: root.dragging = active
        onCentroidChanged: if (active) root.seeked(root.valueAt(centroid.position.x))
    }
}
