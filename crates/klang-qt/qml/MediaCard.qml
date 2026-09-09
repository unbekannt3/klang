// One item in a carousel or grid: album, playlist, mix or artist.
//
// Hover behaves as it does in sone: the artwork scales up inside a clipped
// frame while a scrim and the controls fade and rise into place, and the
// card's own background lifts. Artists get a circular cover with the play
// button centred instead of the bottom row.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

Rectangle {
    id: root

    property string title: ""
    property string subtitle: ""
    property string image: ""
    /// "album" | "playlist" | "mix" | "artist" | "track"
    property string kind: "album"
    /// Drawn filled when the item is already in the library.
    property bool favorited: false
    /// Hides the hover overlay where an item cannot be played or saved.
    property bool showControls: true
    /// FavoritesController has no endpoint for every kind — a video's heart
    /// would be a control that does nothing.
    property bool showFavorite: true

    signal activated()
    /// The hover play button, distinct from opening the item.
    signal playRequested()
    signal favoriteToggled()
    /// The overlay's "…" button, and right-click, in this card's coordinates.
    signal contextRequested(real x, real y)

    readonly property bool circular: kind === "artist"

    implicitWidth: Theme.cardSize
    implicitHeight: coverFrame.height + captions.implicitHeight
                    + Theme.cardPadding * 3

    radius: Theme.radius
    // A round cover's corners are painted over in the card's colour, and the
    // Shape that does it does not repaint when that colour animates, so an
    // artist card keeps one background and shows its hover state through the
    // play button alone.
    color: hover.hovered && !circular ? Theme.surfaceHover : Theme.elevated

    Behavior on color {
        ColorAnimation { duration: Theme.durationSlow }
    }

    HoverHandler { id: hover }
    TapHandler { onSingleTapped: root.activated() }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onSingleTapped: (event) => root.contextRequested(event.position.x, event.position.y)
    }

    /// A round control over the artwork.
    component OverlayButton: Rectangle {
        id: button
        required property string iconName
        property color iconColor: Theme.textOnImage
        signal activated()

        width: 32
        height: 32
        radius: Theme.radiusFull
        color: buttonHover.hovered ? Theme.scrimStrong : Theme.scrim

        Behavior on color { ColorAnimation { duration: Theme.duration } }

        HoverHandler { id: buttonHover }
        TapHandler { onSingleTapped: button.activated() }

        Icon {
            anchors.centerIn: parent
            width: 16
            height: 16
            name: button.iconName
            color: button.iconColor
        }
    }

    // Anchored rather than laid out: a ColumnLayout filling the card ignored
    // its own margins here, and the cover ended up flush with the card edge.
    Item {
        id: coverFrame
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.cardPadding
        height: width
        clip: true

        CoverArt {
            anchors.fill: parent
            radius: root.circular ? width / 2 : Theme.radiusSm
            uuid: root.image
            placeholderGlyph: root.kind === "artist" ? "☺"
                            : root.kind === "playlist" ? "≡"
                            : "♪"

            // Scaled rather than resized, so the frame's clip holds it
            // and nothing in the layout moves.
            scale: hover.hovered && root.showControls ? 1.05 : 1

            Behavior on scale {
                NumberAnimation {
                    duration: Theme.durationSlow
                    easing.type: Easing.OutCubic
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: root.showControls
            radius: root.circular ? width / 2 : Theme.radiusSm
            color: Theme.scrimSoft
            opacity: hover.hovered ? 1 : 0

            Behavior on opacity { NumberAnimation { duration: Theme.duration } }
        }

        // Artists have no bottom row: one large play button in the middle.
        Item {
            anchors.centerIn: parent
            visible: root.showControls && root.circular
            width: 48
            height: 48
            opacity: hover.hovered ? 1 : 0

            Behavior on opacity { NumberAnimation { duration: Theme.duration } }

            HoverHandler { id: centreHover }
            TapHandler { onSingleTapped: root.playRequested() }

            Icon {
                anchors.centerIn: parent
                width: 28
                height: 28
                name: "play"
                color: Theme.textOnImage
                scale: centreHover.hovered ? 1.1 : 1

                Behavior on scale { NumberAnimation { duration: Theme.duration } }
            }
        }

        // The controls share one fade and one rise, so they read as a
        // single overlay rather than three separate buttons.
        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: hover.hovered ? 0 : -Theme.spaceSm
            height: 40 + Theme.spaceSm * 2
            visible: root.showControls && !root.circular
            opacity: hover.hovered ? 1 : 0

            Behavior on opacity { NumberAnimation { duration: Theme.duration } }
            Behavior on anchors.bottomMargin {
                NumberAnimation {
                    duration: Theme.duration
                    easing.type: Easing.OutCubic
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: Theme.spaceSm
                width: 40
                height: 40
                radius: Theme.radiusFull
                color: Theme.accent
                scale: playHover.hovered ? 1.1 : 1

                Behavior on scale { NumberAnimation { duration: Theme.duration } }

                HoverHandler { id: playHover }
                TapHandler { onSingleTapped: root.playRequested() }

                Icon {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: 1
                    width: 20
                    height: 20
                    name: "play"
                    color: Theme.onAccent
                }
            }

            RowLayout {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Theme.spaceSm
                spacing: Theme.spaceXs

                OverlayButton {
                    iconName: "more"
                    onActivated: root.contextRequested(x, y)
                }

                OverlayButton {
                    visible: root.showFavorite
                    iconName: root.favorited ? "heart-filled" : "heart"
                    iconColor: root.favorited ? Theme.accent : Theme.textOnImage
                    onActivated: root.favoriteToggled()
                }
            }
        }
    }

    ColumnLayout {
        id: captions
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: coverFrame.bottom
        anchors.leftMargin: Theme.cardPadding
        anchors.rightMargin: Theme.cardPadding
        anchors.topMargin: Theme.cardPadding
        spacing: Theme.spaceXs

        Text {
            Layout.fillWidth: true
            text: root.title
            elide: Text.ElideRight
            maximumLineCount: 1
            horizontalAlignment: root.circular ? Text.AlignHCenter : Text.AlignLeft
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
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            horizontalAlignment: root.circular ? Text.AlignHCenter : Text.AlignLeft
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            color: Theme.textMuted
        }
    }
}
