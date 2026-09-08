// One item in a carousel or grid: album, playlist, mix or artist.
// Artists get a circular cover, matching tidal.com.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    property string title: ""
    property string subtitle: ""
    property string image: ""
    /// "album" | "playlist" | "mix" | "artist" | "track"
    property string kind: "album"

    signal activated()
    /// The hover play button, distinct from opening the item.
    signal playRequested()
    /// Right-click, in this card's coordinates.
    signal contextRequested(real x, real y)

    implicitWidth: Theme.cardSize
    implicitHeight: Theme.cardSize + 52

    readonly property bool circular: kind === "artist"

    Rectangle {
        anchors.fill: parent
        anchors.margins: -Theme.spaceSm
        radius: Theme.radiusSm
        color: hover.hovered ? Theme.hlFaint : "transparent"

        Behavior on color {
            ColorAnimation { duration: Theme.durationFast }
        }
    }

    HoverHandler { id: hover }
    TapHandler { onSingleTapped: root.activated() }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onSingleTapped: (event) => root.contextRequested(event.position.x, event.position.y)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spaceSm

        Item {
            Layout.preferredWidth: root.width
            Layout.preferredHeight: root.width

            CoverArt {
                anchors.fill: parent
                radius: root.circular ? width / 2 : 0
                uuid: root.image
                placeholderGlyph: root.kind === "artist" ? "☺"
                                : root.kind === "playlist" ? "≡"
                                : "♪"
            }

            // Play affordance, revealed on hover like the web client.
            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Theme.spaceSm
                width: 40
                height: 40
                radius: width / 2
                color: Theme.accent
                opacity: hover.hovered ? 1 : 0
                scale: hover.hovered ? 1 : 0.85

                Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }
                Behavior on scale { NumberAnimation { duration: Theme.durationFast } }

                // Only clickable once visible, so a stray tap on a cover
                // corner does not start playback.
                TapHandler {
                    enabled: hover.hovered
                    onSingleTapped: root.playRequested()
                }

                Icon {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: 1
                    width: 18
                    height: 18
                    name: "play"
                    color: Theme.onAccent
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: root.title
            elide: Text.ElideRight
            maximumLineCount: 1
            horizontalAlignment: root.circular ? Text.AlignHCenter : Text.AlignLeft
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textPrimary
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: -Theme.spaceXs
            visible: root.subtitle.length > 0
            text: root.subtitle
            elide: Text.ElideRight
            maximumLineCount: 1
            horizontalAlignment: root.circular ? Text.AlignHCenter : Text.AlignLeft
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            color: Theme.textMuted
        }

        Item { Layout.fillHeight: true }
    }
}
