// The cover's colours spread out behind a panel.
//
// The 160px bracket stretched over the panel is blur enough on its own, so
// this needs no shader and works under the software renderer too.

import QtQuick
import me.unbk.klang

Item {
    id: root

    /// TIDAL image UUID, as CoverArt takes it.
    property string uuid: ""
    /// How much of the panel's own colour stays on top, at the two edges.
    /// Strongest where the artwork is, quietest where body text runs: the
    /// text ramp is derived against Theme.surfaceHover and the ground has to
    /// stay there or below for it to hold.
    property real veilNear: 0.80
    property real veilFar: 0.95
    property color veilColor: Theme.base

    clip: true

    Rectangle {
        anchors.fill: parent
        color: root.veilColor
    }

    Image {
        // Oversized and centred: bilinear upscaling softens the edges, and
        // the overhang keeps the crop's borders off-screen.
        anchors.centerIn: parent
        width: parent.width * 1.6
        height: parent.height * 1.6
        asynchronous: true
        cache: true
        sourceSize.width: 160
        sourceSize.height: 160
        fillMode: Image.PreserveAspectCrop
        smooth: true
        source: root.uuid ? Theme.coverUrl(root.uuid, 160) : ""
        opacity: status === Image.Ready ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.durationSlow }
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.alpha(root.veilColor, root.veilNear) }
            GradientStop { position: 0.55; color: Qt.alpha(root.veilColor, root.veilFar) }
            GradientStop { position: 1.0; color: Qt.alpha(root.veilColor, root.veilFar) }
        }
    }
}
