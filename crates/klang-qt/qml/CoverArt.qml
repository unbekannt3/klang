// TIDAL's image CDN needs no auth, so Qt fetches directly and uses its own
// network cache. This bypasses klang-core's disk cache and proxy settings;
// routing thumbnails through the core would need a QQuickImageProvider.

import QtQuick
import QtQuick.Shapes
import me.unbk.klang

Rectangle {
    id: root

    /// TIDAL image UUID, or a full URL.
    property string uuid: ""
    property string placeholderGlyph: "♪"

    color: Theme.inset
    // A zoomed image would otherwise spill past the corner mask, which only
    // covers this item's own bounds.
    clip: true

    /// True once the radius makes a circle, i.e. an artist's cover.
    readonly property bool rounded: radius >= Math.min(width, height) / 2 && width > 0
    /// What shows through outside a round cover — the surface behind it.
    property color surroundColor: Theme.base
    /// Zooms the artwork without moving the frame, so a round cover's mask
    /// keeps cutting the same circle.
    property real zoom: 1

    Text {
        anchors.centerIn: parent
        visible: image.status !== Image.Ready
        text: root.placeholderGlyph
        font.pixelSize: Math.max(11, root.height * 0.34)
        color: Theme.textFaint
    }

    Image {
        id: image
        anchors.fill: parent
        asynchronous: true
        cache: true
        // Cap the texture at the drawn size, not the source resolution. The
        // CDN bracket is picked from the same device-pixel figure, or a 2x
        // display would fetch the bracket below what it draws and upscale.
        sourceSize.width: Math.round(root.width * Screen.devicePixelRatio)
        sourceSize.height: Math.round(root.height * Screen.devicePixelRatio)
        fillMode: Image.PreserveAspectCrop
        scale: root.zoom
        source: Theme.coverUrl(root.uuid, root.width * Screen.devicePixelRatio)
        opacity: status === Image.Ready ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.duration }
        }
    }

    // A Rectangle's radius does not clip its children and `clip` is
    // rectangular, so a round cover is cut by painting the surround back over
    // the corners. A layer mask would do it in one pass but renders nothing
    // under Qt's software backend, which is what the headless tests use.
    Shape {
        anchors.fill: parent
        visible: root.rounded
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.surroundColor
            strokeWidth: -1
            fillRule: ShapePath.OddEvenFill

            // Overshoot by a pixel: the fill's own edge antialiases against
            // the cover and leaves a seam when it lands exactly on it.
            PathRectangle {
                x: -1
                y: -1
                width: root.width + 2
                height: root.height + 2
            }
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: Math.min(root.width, root.height) / 2
                radiusY: Math.min(root.width, root.height) / 2
                startAngle: 0
                sweepAngle: 360
            }
        }
    }
}
