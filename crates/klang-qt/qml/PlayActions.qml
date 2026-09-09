// The Play / Shuffle pair every track-list page carries above its rows.
//
// Shuffle keeps the picked track first and shuffles the rest around it (see
// Queue::set_context), so turning shuffle on before starting is all it takes.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

RowLayout {
    id: root

    required property var player
    /// JSON string of track rows, in the order they should play.
    required property string tracks
    /// Playback source label, e.g. "album:12345".
    required property string source

    spacing: Theme.space

    function playAll() {
        if (root.tracks.length > 2)
            root.player.play_context(root.tracks, 0, root.source)
    }

    function shufflePlay() {
        if (!root.player.shuffle)
            root.player.toggle_shuffle()
        root.playAll()
    }

    component ActionButton: Rectangle {
        id: button
        required property string label
        required property string iconName
        property bool primary: false
        signal activated()

        implicitWidth: content.implicitWidth + Theme.spaceLg
        implicitHeight: 44
        radius: Theme.radiusFull
        color: button.primary
             ? (hover.hovered ? Theme.accentHover : Theme.accent)
             : (hover.hovered ? Theme.buttonHover : Theme.button)

        HoverHandler { id: hover }
        TapHandler { onSingleTapped: button.activated() }

        RowLayout {
            id: content
            anchors.centerIn: parent
            spacing: Theme.spaceXs

            Icon {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                name: button.iconName
                color: button.primary ? Theme.onAccent : Theme.textPrimary
            }

            Text {
                text: button.label
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.weight: Font.Bold
                color: button.primary ? Theme.onAccent : Theme.textPrimary
            }
        }
    }

    ActionButton {
        label: Tr.t("Play")
        iconName: "play"
        primary: true
        onActivated: root.playAll()
    }

    ActionButton {
        label: Tr.t("Shuffle")
        iconName: "shuffle"
        onActivated: root.shufflePlay()
    }
}
