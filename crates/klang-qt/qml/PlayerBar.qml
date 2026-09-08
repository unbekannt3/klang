// Transport bar. 88 px tall, full width, matching tidal.com.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

Rectangle {
    id: root

    required property var player

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
        property string glyph: ""
        property int glyphSize: Theme.fontSizeLg
        property bool primary: false
        property bool active: true
        signal clicked()

        implicitWidth: primary ? 40 : 32
        implicitHeight: primary ? 40 : 32
        radius: Theme.radiusFull
        color: primary ? Theme.textPrimary
             : hover.hovered ? Theme.hlMed : "transparent"
        opacity: btn.active ? 1 : 0.4

        HoverHandler { id: hover; enabled: btn.active }
        TapHandler { enabled: btn.active; onSingleTapped: btn.clicked() }

        Text {
            anchors.centerIn: parent
            text: btn.glyph
            font.pixelSize: btn.glyphSize
            color: btn.primary ? Theme.base : Theme.textSecondary
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

            CoverArt {
                Layout.preferredWidth: Theme.coverThumb + 16
                Layout.preferredHeight: Theme.coverThumb + 16
                uuid: root.player.cover
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

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

                IconButton { glyph: "⏮" }

                IconButton {
                    primary: true
                    glyph: root.player.playing ? "❚❚" : "▶"
                    glyphSize: root.player.playing ? Theme.fontSizeSm : Theme.fontSizeLg
                    active: !root.player.busy
                    onClicked: root.player.toggle()
                }

                IconButton { glyph: "⏭" }
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

            Text {
                text: "🔊"
                font.pixelSize: Theme.fontSize
                color: Theme.textMuted
            }

            ProgressSlider {
                id: volume
                Layout.preferredWidth: 80
                to: 1
                value: 1
                onSeeked: (v) => root.player.set_output_volume(v)
            }
        }
    }
}
