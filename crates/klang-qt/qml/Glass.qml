// tidal.com's chrome material: a blurred, saturated view of whatever is
// behind, under a dark tint. Their values, taken from the running site —
// `backdrop-filter: blur(20px) saturate(1.8)` over `rgba(40,40,40,0.75)`.
//
// Qt has no backdrop filter, so the blur is a live copy of `behind` fed
// through MultiEffect. Under the software renderer MultiEffect draws nothing
// and only the tint remains, which is most of the look anyway at 75% opacity.

import QtQuick
import QtQuick.Effects
import me.unbk.klang

Item {
    id: root

    /// What to sample. Must not be an ancestor of this item, or the copy
    /// feeds back into itself.
    property Item behind: null
    property color tint: Qt.rgba(40 / 255, 40 / 255, 40 / 255, 0.75)
    property real radius: 0

    ShaderEffectSource {
        id: source
        anchors.fill: parent
        visible: false
        live: true
        hideSource: false
        sourceItem: root.behind
        sourceRect: root.behind
            ? Qt.rect(root.mapToItem(root.behind, 0, 0).x,
                      root.mapToItem(root.behind, 0, 0).y,
                      root.width, root.height)
            : Qt.rect(0, 0, 0, 0)
    }

    MultiEffect {
        anchors.fill: parent
        source: source
        visible: root.behind !== null
                 && GraphicsInfo.api !== GraphicsInfo.Software
        blurEnabled: true
        blur: 1.0
        blurMax: 48
        saturation: 0.8
    }

    Rectangle {
        anchors.fill: parent
        color: root.tint
        radius: root.radius
    }
}
