// Shared track list. Every page that shows tracks uses this, so swapping the
// JSON model for a real QAbstractListModel later is a change in one file.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    /// JSON string or array of {id, title, artist, album, duration, quality}.
    property var tracks: []
    property string emptyText: "Nothing here"
    property bool loading: false
    /// Track id to mark as playing.
    property int activeId: 0
    property bool numbered: true
    /// TIDAL shows both on track lists; album views hide them.
    property bool showBpm: true
    property bool showKey: true
    /// Album views already show one big cover, so their rows hide the thumbnail.
    property bool showCovers: true

    signal trackActivated(int id, string title, string artist, real duration, string cover)

    function rows() {
        if (typeof tracks === "string")
            return JSON.parse(tracks || "[]")
        return tracks || []
    }

    ListView {
        id: view
        anchors.fill: parent
        clip: true
        model: root.rows()
        currentIndex: -1
        reuseItems: true

        HoverHandler { id: listHover }

        WheelScroller {
            view: view
            rowHeight: Theme.rowHeight
        }

        QQC2.ScrollBar.vertical: ThemedScrollBar {
            listHovered: listHover.hovered
        }

        // Column header, TIDAL-style: thin uppercase labels over a hairline.
        header: Item {
            width: view.width
            height: 34

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spaceLg
                // Extra on the right so the overlay scrollbar never sits on the
                // LENGTH column.
                anchors.rightMargin: Theme.spaceLg + Theme.spaceSm
                anchors.bottomMargin: Theme.spaceXs
                spacing: Theme.space

                Text {
                    visible: root.numbered
                    Layout.preferredWidth: 28
                    horizontalAlignment: Text.AlignRight
                    text: "#"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm - 1
                    font.letterSpacing: 1
                    color: Theme.textFaint
                }

                Text {
                    Layout.fillWidth: true
                    text: "TITLE"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm - 1
                    font.letterSpacing: 1
                    color: Theme.textFaint
                }

                Text {
                    visible: root.showBpm
                    Layout.preferredWidth: 52
                    horizontalAlignment: Text.AlignRight
                    text: "BPM"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm - 1
                    font.letterSpacing: 1
                    color: Theme.textFaint
                }

                Text {
                    visible: root.showKey
                    Layout.preferredWidth: 48
                    horizontalAlignment: Text.AlignRight
                    text: "KEY"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm - 1
                    font.letterSpacing: 1
                    color: Theme.textFaint
                }

                Text {
                    Layout.preferredWidth: 64
                    horizontalAlignment: Text.AlignRight
                    text: "LENGTH"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm - 1
                    font.letterSpacing: 1
                    color: Theme.textFaint
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Theme.spaceLg
                anchors.rightMargin: Theme.spaceLg
                height: 1
                color: Theme.border
            }
        }

        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index

            readonly property bool active: modelData.id === root.activeId

            width: view.width - Theme.spaceLg * 2
            x: Theme.spaceLg
            height: Theme.rowHeight
            radius: Theme.radiusXs
            color: hover.hovered ? Theme.hlFaint : "transparent"

            HoverHandler { id: hover }
            TapHandler {
                onSingleTapped: root.trackActivated(row.modelData.id, row.modelData.title,
                                                    row.modelData.artist, row.modelData.duration,
                                                    row.modelData.cover || "")
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spaceSm
                anchors.rightMargin: Theme.spaceSm + Theme.spaceSm
                spacing: Theme.space

                Text {
                    visible: root.numbered
                    Layout.preferredWidth: 28
                    horizontalAlignment: Text.AlignRight
                    text: row.active ? "▶" : (row.index + 1)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: row.active ? Theme.accent : Theme.textFaint
                }

                CoverArt {
                    visible: root.showCovers
                    Layout.preferredWidth: Theme.coverThumb
                    Layout.preferredHeight: Theme.coverThumb
                    uuid: row.modelData.cover || ""
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.title
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        color: row.active ? Theme.accent : Theme.textPrimary
                    }

                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.album
                              ? row.modelData.artist + " · " + row.modelData.album
                              : row.modelData.artist
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        color: Theme.textMuted
                    }
                }

                // Quality badge, only when the API told us something.
                Rectangle {
                    visible: !!row.modelData.quality
                    implicitWidth: qualityText.implicitWidth + Theme.spaceSm
                    implicitHeight: 18
                    radius: Theme.radiusXs
                    color: Theme.hlMed

                    Text {
                        id: qualityText
                        anchors.centerIn: parent
                        text: row.modelData.quality
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm - 2
                        font.letterSpacing: 0.5
                        color: Theme.textSecondary
                    }
                }

                // TIDAL exposes bpm and key on the track payload; it prints a
                // dash where the catalogue has no analysis for a track.
                Text {
                    visible: root.showBpm
                    Layout.preferredWidth: 52
                    horizontalAlignment: Text.AlignRight
                    text: row.modelData.bpm ? row.modelData.bpm : "–"
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: row.modelData.bpm ? Theme.textSecondary : Theme.textDisabled
                }

                Item {
                    visible: root.showKey
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 20

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !!row.modelData.key
                        width: keyText.implicitWidth + Theme.spaceSm
                        height: 20
                        radius: Theme.radiusXs
                        color: Theme.hlMed

                        Text {
                            id: keyText
                            anchors.centerIn: parent
                            text: row.modelData.key || ""
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm - 1
                            font.weight: Font.DemiBold
                            color: Theme.accent
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !row.modelData.key
                        text: "–"
                        font.family: Theme.monoFamily
                        font.pixelSize: Theme.fontSizeSm
                        color: Theme.textDisabled
                    }
                }

                Text {
                    Layout.preferredWidth: 64
                    horizontalAlignment: Text.AlignRight
                    text: Format.duration(row.modelData.duration)
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textFaint
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: view.count === 0 && !root.loading
        text: root.emptyText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeLg
        color: Theme.textFaint
    }

    QQC2.BusyIndicator {
        anchors.centerIn: parent
        running: root.loading
    }
}
