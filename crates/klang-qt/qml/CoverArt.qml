// Album or artist artwork.
//
// TIDAL serves images from a public CDN with no auth, so Qt's Image fetches
// them directly and keeps its own network cache. That bypasses klang-core's
// disk cache and proxy settings — a deliberate trade for now; routing every
// thumbnail through the core would need a QQuickImageProvider.
//
// No corner radius by default: tidal.com renders covers square.

import QtQuick
import me.unbk.klang

Rectangle {
    id: root

    /// TIDAL image UUID. A full URL is passed through unchanged.
    property string uuid: ""
    /// Shown while loading and when there is no artwork.
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
        // Decoded off the GUI thread so a long list never stutters.
        asynchronous: true
        cache: true
        // Cap the texture at what is drawn, not the source resolution.
        sourceSize.width: Math.round(root.width * Screen.devicePixelRatio)
        sourceSize.height: Math.round(root.height * Screen.devicePixelRatio)
        fillMode: Image.PreserveAspectCrop
        source: root.url(root.uuid, root.width)
        opacity: status === Image.Ready ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.duration }
        }
    }
}
