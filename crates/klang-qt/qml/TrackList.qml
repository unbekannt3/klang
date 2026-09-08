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

    signal trackActivated(int id, string title, string artist, real duration)

    function rows() {
        if (typeof tracks === "string")
            return JSON.parse(tracks || "[]")
        return tracks || []
    }

    ListView {
        id: view
        anchors.fill: parent
        anchors.leftMargin: Theme.spaceLg
        anchors.rightMargin: Theme.spaceLg
        clip: true
        model: root.rows()
        currentIndex: -1
        reuseItems: true

        // Column header, TIDAL-style: thin uppercase labels over a hairline.
        header: Item {
            width: view.width
            height: 34

            RowLayout {
                anchors.fill: parent
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
                    Layout.preferredWidth: 90
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
                width: parent.width
                height: 1
                color: Theme.border
            }
        }

        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index

            readonly property bool active: modelData.id === root.activeId

            width: view.width
            height: Theme.rowHeight
            radius: Theme.radiusXs
            color: hover.hovered ? Theme.hlFaint : "transparent"

            HoverHandler { id: hover }
            TapHandler {
                onSingleTapped: root.trackActivated(row.modelData.id, row.modelData.title,
                                                    row.modelData.artist, row.modelData.duration)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spaceSm
                anchors.rightMargin: Theme.spaceSm
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

                Text {
                    Layout.preferredWidth: 90
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
