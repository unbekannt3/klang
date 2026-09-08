// A titled horizontal strip of MediaCards, the shape TIDAL's home page is
// built from.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

ColumnLayout {
    id: root

    property string title: ""
    /// Array of {id, title, subtitle, image, kind}.
    property var items: []

    signal itemActivated(var item)

    spacing: Theme.spaceSm

    Text {
        Layout.leftMargin: Theme.spaceLg
        text: root.title
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeHeading
        font.weight: Font.Bold
        color: Theme.textPrimary
    }

    ListView {
        id: strip
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.cardSize + 76
        Layout.leftMargin: Theme.spaceLg
        Layout.rightMargin: Theme.spaceLg
        orientation: ListView.Horizontal
        spacing: Theme.spaceLg
        clip: true
        reuseItems: true
        model: root.items
        boundsBehavior: Flickable.StopAtBounds

        // A vertical wheel over a horizontal strip should move the page, not
        // the strip, so no WheelScroller here — drag or the arrows instead.

        delegate: MediaCard {
            required property var modelData
            title: modelData.title || ""
            subtitle: modelData.subtitle || ""
            image: modelData.image || ""
            kind: modelData.kind || "album"
            onActivated: root.itemActivated(modelData)
        }
    }
}
