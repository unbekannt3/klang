// TIDAL's image CDN needs no auth, so Qt fetches directly and uses its own
// network cache. This bypasses klang-core's disk cache and proxy settings;
// routing thumbnails through the core would need a QQuickImageProvider.

import QtQuick
import me.unbk.klang

Rectangle {
    id: root

    /// TIDAL image UUID, or a full URL.
    property string uuid: ""
    property string placeholderGlyph: "♪"

    color: Theme.inset

    function url(id, px) {
        if (!id)
            return ""
        if (id.startsWith("http"))
            return id
        // Dashes become path separators; the CDN serves 160/320/640/1280.
        const path = id.replace(/-/g, "/")
        const valid = px <= 160 ? 160 : px <= 320 ? 320 : px <= 640 ? 640 : 1280
        return "https://resources.tidal.com/images/" + path + "/" + valid + "x" + valid + ".jpg"
    }

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
        source: root.url(root.uuid, root.width * Screen.devicePixelRatio)
        opacity: status === Image.Ready ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.duration }
        }
    }
}
