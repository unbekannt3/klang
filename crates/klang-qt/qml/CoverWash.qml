// The cover's colours spread out behind a panel.
//
// The 160px bracket stretched over the panel is blur enough on its own, so
// this needs no shader and works under the software renderer too.

import QtQuick
import QtQuick.Effects
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
    /// Covers are rarely as saturated as the wash wants to look.
    property real saturation: 0.6
    /// One full turn, in ms. tidal.com drifts its blur round slowly enough
    /// that the movement reads without ever drawing the eye.
    property int turn: 150000

    /// MultiEffect draws nothing under the software renderer, so there the
    /// upscaled image is the blur; anywhere else it would double up with it.
    readonly property bool effects: GraphicsInfo.api !== GraphicsInfo.Software

    clip: true

    Rectangle {
        anchors.fill: parent
        color: root.veilColor
    }

    // Square and wide enough that no corner of the panel is ever uncovered
    // as it turns, which is the whole reason it is not simply the panel size.
    Item {
        id: rotator
        anchors.centerIn: parent
        width: Math.round(Math.hypot(root.width, root.height) * 1.08)
        height: width

        NumberAnimation on rotation {
            running: Theme.animated && root.uuid.length > 0
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: root.turn
        }

        Image {
            id: art
            // Upscaling a 160px bracket is the whole blur under the software
            // renderer, where the effect below draws nothing.
            anchors.fill: parent
            asynchronous: true
            cache: true
            sourceSize.width: 320
            sourceSize.height: 320
            fillMode: Image.PreserveAspectCrop
            smooth: true
            source: root.uuid ? Theme.coverUrl(root.uuid, 320) : ""
            opacity: status === Image.Ready ? 1 : 0
            visible: !root.effects
            layer.enabled: root.effects
            layer.smooth: true

            Behavior on opacity {
                NumberAnimation { duration: Theme.durationSlow }
            }
        }

        // The colour a flat dark veil would otherwise wash out: pushing
        // saturation up lets the veil stay dark enough for the text on top.
        MultiEffect {
            anchors.fill: art
            source: art
            visible: root.effects
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            saturation: root.saturation
            opacity: art.opacity
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
