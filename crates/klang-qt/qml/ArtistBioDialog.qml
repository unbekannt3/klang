// The full artist bio, with the albums and artists it mentions as links.
//
// TIDAL marks those up as [wimpLink artistId="…"]Name[/wimpLink] and hands the
// text through raw, so the markup is turned into rich text here and the links
// are routed like any other navigation.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    property string artistName: ""
    property string bio: ""
    property bool open: false

    signal closeRequested()
    signal openArtist(int artistId)
    signal openAlbum(int albumId)

    anchors.fill: parent
    visible: root.open
    enabled: root.open

    Keys.onEscapePressed: root.closeRequested()

    /// TIDAL's own markup, plus the paragraph breaks its plain text uses.
    function richText(text) {
        if (!text)
            return ""
        // Escaped first so the bio's own prose cannot inject markup, then the
        // one tag TIDAL really does put in the text is let back through.
        const escaped = text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        return escaped
            .replace(/&lt;br\s*\/?&gt;/gi, "<br>")
            .replace(/\[wimpLink artistId="(\d+)"\]([\s\S]*?)\[\/wimpLink\]/g,
                     '<a href="artist:$1">$2</a>')
            .replace(/\[wimpLink albumId="(\d+)"\]([\s\S]*?)\[\/wimpLink\]/g,
                     '<a href="album:$1">$2</a>')
            // Anything else in brackets is markup we do not render.
            .replace(/\[\/?[a-zA-Z][^\]]*\]/g, "")
            .replace(/\n/g, "<br>")
    }

    ModalShield {
        blocksPage: true
        scrim: Qt.alpha(Theme.overlay, 0.55)
        onDismissed: root.closeRequested()
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.spaceXl * 2, 680)
        height: Math.min(parent.height - Theme.spaceXl * 2, 560)
        radius: Theme.radiusLg
        color: Theme.elevated
        border.color: Theme.border
        border.width: 1

        ModalShield {}

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spaceLg
            spacing: Theme.space

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space

                Text {
                    Layout.fillWidth: true
                    text: root.artistName
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeHeading
                    font.weight: Font.Bold
                    color: Theme.textPrimary
                }

                Item {
                    implicitWidth: 28
                    implicitHeight: 28

                    Icon {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        name: "close"
                        color: closeHover.hovered ? Theme.textPrimary : Theme.textMuted
                    }

                    HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onSingleTapped: root.closeRequested() }
                }
            }

            QQC2.ScrollView {
                id: bioScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth

                Text {
                    // A ScrollView's content sizes itself, so `parent.width`
                    // here is the flickable's content width, not the view's.
                    width: bioScroll.availableWidth
                    text: root.richText(root.bio)
                    textFormat: Text.RichText
                    wrapMode: Text.WordWrap
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: Theme.textSecondary
                    linkColor: Theme.accent

                    onLinkActivated: (link) => {
                        const id = parseInt(link.split(":")[1])
                        if (link.startsWith("artist:"))
                            root.openArtist(id)
                        else if (link.startsWith("album:"))
                            root.openAlbum(id)
                        root.closeRequested()
                    }

                    HoverHandler {
                        cursorShape: parent.hoveredLink.length > 0
                                     ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                }
            }
        }
    }
}
