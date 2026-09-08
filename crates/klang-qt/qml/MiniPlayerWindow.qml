// Detached transport window, sone's MiniPlayer.
//
// Frameless and always on top, sized by the user; the layout switches between
// three tiers as it is resized, the way sone's does — a tall window shows the
// cover, a short one becomes a single row.

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import me.unbk.klang

Window {
    id: root

    required property var player
    /// FavoritesController; when unset the heart is hidden.
    property var favorites: null

    readonly property string tier: height < 100 ? "narrow"
                                 : height < 220 ? "compact"
                                 : "full"
    readonly property bool loved: !!favorites && player.track_id !== 0
        && favorites.revision >= 0 && favorites.is_track(player.track_id)

    width: 340
    height: 320
    minimumWidth: 240
    minimumHeight: 72
    color: Theme.base
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    title: "klang"

    component IconButton: Rectangle {
        id: button
        property string iconName: ""
        property int iconSize: 18
        property bool primary: false
        property bool on: false
        signal clicked()

        implicitWidth: primary ? 36 : 28
        implicitHeight: primary ? 36 : 28
        radius: Theme.radiusFull
        color: primary ? Theme.textPrimary
             : hover.hovered ? Theme.hlMed : "transparent"

        HoverHandler { id: hover }
        TapHandler { onSingleTapped: button.clicked() }

        Icon {
            anchors.centerIn: parent
            width: button.iconSize
            height: button.iconSize
            name: button.iconName
            color: button.primary ? Theme.base
                 : button.on ? Theme.accent
                 : hover.hovered ? Theme.textPrimary
                 : Theme.textSecondary
        }
    }

    // The whole background drags the window: a frameless window has no
    // titlebar to grab, and the controls sit above this handler.
    DragHandler {
        target: null
        onActiveChanged: {
            if (active)
                root.startSystemMove()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.space
        spacing: Theme.spaceSm

        CoverArt {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(parent.width - Theme.spaceXl,
                                            root.height - 150)
            Layout.preferredHeight: Layout.preferredWidth
            visible: root.tier === "full"
            uuid: root.player.cover
            radius: Theme.radiusSm
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spaceSm

            CoverArt {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                visible: root.tier !== "full"
                uuid: root.player.cover
                radius: Theme.radiusXs
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: root.player.title
                    elide: Text.ElideRight
                    horizontalAlignment: root.tier === "full" ? Text.AlignHCenter : Text.AlignLeft
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.weight: Font.DemiBold
                    color: Theme.textPrimary
                }

                Text {
                    Layout.fillWidth: true
                    text: root.player.artist
                    elide: Text.ElideRight
                    horizontalAlignment: root.tier === "full" ? Text.AlignHCenter : Text.AlignLeft
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textMuted
                }
            }

            IconButton {
                visible: root.tier === "narrow"
                iconName: root.player.playing ? "pause" : "play"
                primary: true
                onClicked: root.player.toggle()
            }

            IconButton {
                iconName: "close"
                onClicked: root.hide()
            }
        }

        ProgressSlider {
            Layout.fillWidth: true
            visible: root.tier !== "narrow"
            to: root.player.duration_secs
            value: root.player.position_secs
            onSeeked: (secs) => root.player.seek(secs)
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            visible: root.tier !== "narrow"
            spacing: Theme.spaceSm

            IconButton {
                iconName: "shuffle"
                on: root.player.shuffle
                onClicked: root.player.toggle_shuffle()
            }

            IconButton {
                iconName: "previous"
                onClicked: root.player.previous()
            }

            IconButton {
                iconName: root.player.playing ? "pause" : "play"
                primary: true
                onClicked: root.player.toggle()
            }

            IconButton {
                iconName: "next"
                onClicked: root.player.next()
            }

            IconButton {
                iconName: "repeat"
                on: root.player.repeat !== 0
                onClicked: root.player.toggle_repeat()
            }

            IconButton {
                visible: !!root.favorites && root.player.track_id !== 0
                iconName: root.loved ? "heart-filled" : "heart"
                on: root.loved
                onClicked: root.favorites.toggle_track(root.player.track_id)
            }
        }

        Item { Layout.fillHeight: true }
    }

    ResizeEdges {
        window: root
    }
}
