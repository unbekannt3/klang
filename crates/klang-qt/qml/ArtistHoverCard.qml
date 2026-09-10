// The card tidal.com shows when the cursor rests on an artist's name:
// picture, name, the start of the bio, follow and a way through to the page.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    property var favorites: null
    signal openArtist(int artistId)

    anchors.fill: parent
    visible: card.opacity > 0

    ArtistCardController { id: artist }

    // Held open while the cursor is on the name or on the card itself, so it
    // can be reached to click Follow.
    readonly property bool wanted: ArtistPeek.shown || cardHover.hovered

    onWantedChanged: {
        if (root.wanted)
            openTimer.restart()
        else
            closeTimer.restart()
    }

    property bool ready: false

    Timer {
        id: openTimer
        interval: ArtistPeek.delay
        onTriggered: {
            if (!root.wanted)
                return
            artist.load(ArtistPeek.artistId)
            root.ready = true
        }
    }

    Timer {
        id: closeTimer
        // Long enough to cross the gap from the name to the card.
        interval: 160
        onTriggered: if (!root.wanted) root.ready = false
    }

    readonly property int cardWidth: 300

    Rectangle {
        id: card
        width: root.cardWidth
        implicitHeight: body.implicitHeight + Theme.space * 2
        height: implicitHeight
        // Centred under the name, and flipped above it when the bottom of the
        // window — or the player bar floating over it — leaves no room.
        readonly property real bottomLimit: root.height - Theme.contentBottomInset
                                            - Theme.spaceSm
        readonly property bool below: ArtistPeek.anchor.y + Theme.space + height
                                      <= card.bottomLimit

        x: Math.max(Theme.spaceSm,
                    Math.min(ArtistPeek.anchor.x - width / 2,
                             root.width - width - Theme.spaceSm))
        y: card.below
           ? ArtistPeek.anchor.y + Theme.space
           : Math.max(Theme.spaceSm,
                      ArtistPeek.anchor.y - height - Theme.spaceXl)
        radius: Theme.radiusLg
        color: Theme.elevated
        border.color: Theme.border
        border.width: 1
        opacity: root.ready ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.duration }
        }

        HoverHandler { id: cardHover }

        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.space
            spacing: Theme.spaceSm

            CoverArt {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: root.cardWidth - Theme.space * 2
                Layout.preferredHeight: Layout.preferredWidth
                radius: Theme.radiusSm
                uuid: artist.picture
                placeholderGlyph: "☺"
            }

            Text {
                Layout.fillWidth: true
                text: artist.name
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLg
                font.weight: Font.Bold
                color: Theme.textPrimary
            }

            Text {
                Layout.fillWidth: true
                visible: artist.bio.length > 0
                text: Format.bioPlain(artist.bio)
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textMuted
            }

            RowLayout {
                Layout.topMargin: Theme.spaceXs
                spacing: Theme.spaceSm

                Pill {
                    readonly property bool following: !!root.favorites
                        && root.favorites.revision >= 0
                        && root.favorites.is_artist(artist.artist_id)
                    label: following ? Tr.t("Following") : Tr.t("Follow")
                    accent: following
                    onActivated: if (root.favorites)
                        root.favorites.toggle_artist(artist.artist_id)
                }

                Pill {
                    label: Tr.t("Show more")
                    onActivated: {
                        ArtistPeek.close()
                        root.ready = false
                        root.openArtist(artist.artist_id)
                    }
                }
            }
        }
    }

    component Pill: Rectangle {
        id: pill
        required property string label
        property bool accent: false
        signal activated()

        implicitWidth: pillText.implicitWidth + Theme.space * 2
        implicitHeight: 32
        radius: Theme.radiusFull
        color: pillHover.hovered ? Theme.buttonHover : Theme.button
        border.color: pill.accent ? Theme.accent : "transparent"
        border.width: 1

        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            color: pill.accent ? Theme.accent : Theme.textPrimary
        }

        HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onSingleTapped: pill.activated() }
    }
}
