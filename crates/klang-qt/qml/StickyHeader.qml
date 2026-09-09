// Compact header that slides in once a page's own header scrolls away, the
// way tidal.com's does: thumbnail, title, and the page's actions.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

Rectangle {
    id: root

    required property Flickable flickable
    /// Scroll offset at which the page's own header is gone.
    required property real threshold
    property string title: ""
    property string subtitle: ""
    property string cover: ""

    /// The page's Play/Shuffle row, shown on the right.
    default property alias actions: actionSlot.data

    readonly property bool shown: flickable && flickable.contentY > threshold

    height: 64
    // The glass below carries the surface.
    color: "transparent"
    opacity: shown ? 1 : 0
    visible: opacity > 0
    // Nothing underneath should react while the bar is fading out.
    enabled: shown

    Behavior on opacity {
        NumberAnimation { duration: Theme.durationFast }
    }

    // tidal.com's page header material: the same blur as the player bar over
    // a darker tint, sampling the list it is sitting on.
    Glass {
        anchors.fill: parent
        behind: root.flickable
        tint: Qt.rgba(0, 0, 0, 0.55)
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.border
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spaceLg
        anchors.rightMargin: Theme.spaceLg
        spacing: Theme.space

        CoverArt {
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            visible: root.cover.length > 0
            uuid: root.cover
            radius: Theme.radiusXs
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.weight: Font.Bold
                color: Theme.textPrimary
            }

            Text {
                Layout.fillWidth: true
                visible: root.subtitle.length > 0
                text: root.subtitle
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textMuted
            }
        }

        Item {
            id: actionSlot
            Layout.preferredWidth: childrenRect.width
            Layout.preferredHeight: childrenRect.height
        }
    }
}
