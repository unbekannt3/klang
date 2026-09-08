// Transport bar. 88 px tall, full width, matching tidal.com.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

Rectangle {
    id: root

    required property var player
    property bool shuffle: false
    /// 0 off, 1 all, 2 one.
    property int repeat: 0
    property real volume: 1

    signal nextRequested()
    signal previousRequested()
    signal shuffleToggled()
    signal repeatToggled()
    signal muteToggled()
    signal queueRequested()
    signal expandRequested()

    implicitHeight: Theme.playerBarHeight
    color: Theme.surface

    // Hairline above, so the bar reads as a separate plane.
    Rectangle {
        width: parent.width
        height: 1
        color: Theme.border
    }

    component IconButton: Rectangle {
        id: btn
        property string iconName: ""
        property int iconSize: 20
        property bool primary: false
        property bool active: true
        property bool on: false
        signal clicked()

        implicitWidth: primary ? 40 : 32
        implicitHeight: primary ? 40 : 32
        radius: Theme.radiusFull
        color: primary ? Theme.textPrimary
             : hover.hovered ? Theme.hlMed : "transparent"
        opacity: btn.active ? 1 : 0.4
        scale: primary && hover.hovered ? 1.06 : 1

        Behavior on scale { NumberAnimation { duration: Theme.durationFast } }

        HoverHandler { id: hover; enabled: btn.active }
        TapHandler { enabled: btn.active; onSingleTapped: btn.clicked() }

        Icon {
            anchors.centerIn: parent
            width: btn.iconSize
            height: btn.iconSize
            name: btn.iconName
            color: btn.primary ? Theme.base
                 : btn.on ? Theme.accent
                 : hover.hovered ? Theme.textPrimary
                 : Theme.textSecondary
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spaceLg
        anchors.rightMargin: Theme.spaceLg
        spacing: Theme.spaceLg

        // ---- now playing --------------------------------------------
        RowLayout {
            Layout.preferredWidth: Theme.sidebarWidth
            spacing: Theme.spaceSm

            // Cover and title open the full view, as tidal.com does.
            CoverArt {
                Layout.preferredWidth: Theme.coverThumb + 16
                Layout.preferredHeight: Theme.coverThumb + 16
                uuid: root.player.cover

                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onSingleTapped: root.expandRequested() }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onSingleTapped: root.expandRequested() }

                Text {
                    Layout.fillWidth: true
                    text: root.player.title
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: Theme.textPrimary
                }

                Text {
                    Layout.fillWidth: true
                    text: root.player.artist
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textMuted
                }
            }
        }

        // ---- transport ----------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.spaceXs

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.space

                IconButton {
                    iconName: "shuffle"
                    on: root.shuffle
                    onClicked: root.shuffleToggled()
                }

                IconButton {
                    iconName: "previous"
                    onClicked: root.previousRequested()
                }

                IconButton {
                    primary: true
                    iconName: root.player.playing ? "pause" : "play"
                    iconSize: 22
                    active: !root.player.busy
                    onClicked: root.player.toggle()
                }

                IconButton {
                    iconName: "next"
                    onClicked: root.nextRequested()
                }

                IconButton {
                    iconName: "repeat"
                    on: root.repeat !== 0
                    onClicked: root.repeatToggled()

                    // Repeat-one keeps the loop glyph and marks it with a dot.
                    Rectangle {
                        visible: root.repeat === 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 3
                        width: 3
                        height: 3
                        radius: 1.5
                        color: Theme.accent
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceSm

                Text {
                    text: Format.duration(root.player.position_secs)
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textFaint
                }

                ProgressSlider {
                    id: progress
                    Layout.fillWidth: true
                    to: Math.max(root.player.duration_secs, 1)
                    value: root.player.position_secs
                    onSeeked: (v) => root.player.seek(v)
                }

                Text {
                    text: Format.duration(root.player.duration_secs)
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textFaint
                }
            }
        }

        // ---- right side ---------------------------------------------
        RowLayout {
            Layout.preferredWidth: Theme.sidebarWidth
            spacing: Theme.spaceSm

            Item { Layout.fillWidth: true }

            // What TIDAL actually served, not what was requested.
            Rectangle {
                visible: root.player.quality.length > 0
                implicitWidth: qLabel.implicitWidth + Theme.space
                implicitHeight: 22
                radius: Theme.radiusXs
                color: "transparent"
                border.color: Theme.accent
                border.width: 1

                Text {
                    id: qLabel
                    anchors.centerIn: parent
                    text: root.player.quality
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm - 1
                    font.letterSpacing: 0.5
                    color: Theme.accent
                }
            }

            IconButton {
                iconName: root.volume > 0 ? "volume" : "muted"
                iconSize: 18
                onClicked: root.muteToggled()
            }

            IconButton {
                iconName: "queue"
                iconSize: 18
                onClicked: root.queueRequested()
            }

            ProgressSlider {
                Layout.preferredWidth: 80
                to: 1
                value: root.volume
                onSeeked: (v) => root.player.set_output_volume(v)
            }
        }
    }
}
