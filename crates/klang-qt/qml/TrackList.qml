// Shared track list. Every page that shows tracks uses this, so swapping the
// JSON model for a real QAbstractListModel later is a change in one file.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    /// JSON string or array of row objects; see klang-qt's rows.rs.
    property var tracks: []
    property string emptyText: "Nothing here"
    /// Scroll position is remembered per key across navigation.
    property string scrollKey: ""
    property bool loading: false
    /// Track id to mark as playing.
    property int activeId: 0
    property bool numbered: true
    property bool showBpm: true
    property bool showKey: true
    property bool showCovers: true
    /// An album page already names the album in its header.
    property bool showAlbum: true
    property bool showArtist: true
    /// Shows the filter field tidal.com puts above its lists.
    property bool filterable: false
    /// FavoritesController; when unset the heart column is hidden.
    property var favorites: null

    /// Column the list is sorted by, or "" when the page does not sort.
    property string sortColumn: ""
    property bool sortDescending: true

    signal trackActivated(int index)
    signal contextRequested(int index, real x, real y)
    /// Emitted when a sortable header is clicked; the page re-fetches.
    signal sortRequested(string column)

    component SortableHeading: Item {
        id: heading
        required property string label
        required property string column
        property int alignment: Text.AlignLeft

        readonly property bool sortable: root.sortColumn.length > 0
        readonly property bool active: sortable && root.sortColumn === column

        implicitHeight: 20

        Row {
            anchors.fill: parent
            anchors.rightMargin: heading.alignment === Text.AlignRight ? 0 : undefined
            layoutDirection: heading.alignment === Text.AlignRight ? Qt.RightToLeft : Qt.LeftToRight
            spacing: 3

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: heading.label
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm - 1
                font.letterSpacing: 1
                color: heading.active ? Theme.textSecondary
                     : headingHover.hovered && heading.sortable ? Theme.textMuted
                     : Theme.textFaint
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: heading.active
                text: root.sortDescending ? "\u25be" : "\u25b4"
                font.pixelSize: Theme.fontSizeSm - 2
                color: Theme.textSecondary
            }
        }

        HoverHandler {
            id: headingHover
            enabled: heading.sortable
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            enabled: heading.sortable
            onSingleTapped: root.sortRequested(heading.column)
        }
    }

    property string filterText: ""

    function rows() {
        if (typeof tracks === "string")
            return JSON.parse(tracks || "[]")
        return tracks || []
    }

    /// Rows as rendered: filtered, each carrying the index it has in the
    /// unfiltered list so activating one still plays the right track.
    function visibleRows() {
        const all = root.rows()
        const numbered = all.map((row, i) => ({ row: row, position: i }))
        const needle = root.filterText.trim().toLowerCase()
        if (needle.length === 0)
            return numbered
        return numbered.filter((entry) => {
            const r = entry.row
            return (r.title || "").toLowerCase().includes(needle)
                || (r.artist || "").toLowerCase().includes(needle)
                || (r.album || "").toLowerCase().includes(needle)
        })
    }

    SettingsField {
        id: filterField
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.spaceLg
        anchors.rightMargin: Theme.spaceLg
        anchors.bottomMargin: Theme.space
        visible: root.filterable
        height: visible ? 38 : 0
        placeholder: "Filter by title, artist or album"
        onTextChanged: root.filterText = text
    }

    ListView {
        id: view
        anchors.top: root.filterable ? filterField.bottom : parent.top
        anchors.topMargin: root.filterable ? Theme.space : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        model: root.visibleRows()
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

                SortableHeading {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 3
                    label: "TITLE"
                    column: "NAME"
                }

                SortableHeading {
                    visible: root.showArtist
                    Layout.fillWidth: root.showArtist
                    Layout.preferredWidth: root.showArtist ? 2 : 0
                    label: "ARTIST"
                    column: "ARTIST"
                }

                SortableHeading {
                    visible: root.showAlbum
                    Layout.fillWidth: root.showAlbum
                    Layout.preferredWidth: root.showAlbum ? 2 : 0
                    label: "ALBUM"
                    column: "ALBUM"
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

                Item { Layout.preferredWidth: root.favorites !== null ? 24 : 0 }

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

                SortableHeading {
                    Layout.preferredWidth: 64
                    label: "LENGTH"
                    column: "DURATION"
                    alignment: Text.AlignRight
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
            /// The row's track, and where it sits in the unfiltered list.
            readonly property var track: modelData.row
            readonly property int position: modelData.position

            readonly property bool active: track.id === root.activeId

            width: view.width - Theme.spaceLg * 2
            x: Theme.spaceLg
            height: Theme.rowHeight
            radius: Theme.radiusXs
            color: hover.hovered ? Theme.hlFaint : "transparent"

            HoverHandler { id: hover }
            TapHandler {
                onSingleTapped: root.trackActivated(row.position)
            }
            TapHandler {
                acceptedButtons: Qt.RightButton
                onSingleTapped: (point) => {
                    const p = row.mapToItem(root, point.position.x, point.position.y)
                    root.contextRequested(row.position, p.x, p.y)
                }
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
                    text: row.active ? "▶" : (row.position + 1)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: row.active ? Theme.accent : Theme.textFaint
                }

                CoverArt {
                    visible: root.showCovers
                    Layout.preferredWidth: Theme.coverThumb
                    Layout.preferredHeight: Theme.coverThumb
                    uuid: row.track.cover || ""
                }

                Text {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 3
                    text: row.track.title
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: row.active ? Theme.accent : Theme.textPrimary
                }

                // Artist and album are their own columns, as on tidal.com,
                // rather than one subtitle line under the title.
                Text {
                    visible: root.showArtist
                    Layout.fillWidth: root.showArtist
                    Layout.preferredWidth: root.showArtist ? 2 : 0
                    text: row.track.artist
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: Theme.textMuted
                }

                Text {
                    visible: root.showAlbum
                    Layout.fillWidth: root.showAlbum
                    Layout.preferredWidth: root.showAlbum ? 2 : 0
                    text: row.track.album || ""
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: Theme.textMuted
                }

                // Quality badge, only when the API told us something.
                Rectangle {
                    readonly property bool hiRes: row.track.quality === "HI_RES_LOSSLESS"
                                               || row.track.quality === "HI_RES"

                    visible: !!row.track.quality
                    implicitWidth: qualityText.implicitWidth + Theme.spaceSm
                    implicitHeight: 18
                    radius: Theme.radiusXs
                    color: hiRes ? "transparent" : Theme.hlMed
                    border.color: Theme.hiRes
                    border.width: hiRes ? 1 : 0

                    Text {
                        id: qualityText
                        anchors.centerIn: parent
                        text: Format.qualityLabel(row.track.quality)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm - 2
                        font.letterSpacing: 0.5
                        color: Format.qualityColor(row.track.quality)
                    }
                }

                // TIDAL exposes bpm and key on the track payload; it prints a
                // dash where the catalogue has no analysis for a track.
                Text {
                    visible: root.showBpm
                    Layout.preferredWidth: 52
                    horizontalAlignment: Text.AlignRight
                    text: row.track.bpm ? row.track.bpm : "–"
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: row.track.bpm ? Theme.textSecondary : Theme.textDisabled
                }

                Item {
                    visible: root.showKey
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 20

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !!row.track.key
                        width: keyText.implicitWidth + Theme.spaceSm
                        height: 20
                        radius: Theme.radiusXs
                        color: Theme.hlMed

                        Text {
                            id: keyText
                            anchors.centerIn: parent
                            text: row.track.key || ""
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm - 1
                            font.weight: Font.DemiBold
                            color: Theme.accent
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !row.track.key
                        text: "–"
                        font.family: Theme.monoFamily
                        font.pixelSize: Theme.fontSizeSm
                        color: Theme.textDisabled
                    }
                }

                // The heart shows on hover, or always once favourited.
                Item {
                    visible: root.favorites !== null
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24

                    property bool loved: root.favorites
                        && root.favorites.revision >= 0
                        && root.favorites.is_track(row.track.id)

                    Icon {
                        anchors.centerIn: parent
                        width: 17
                        height: 17
                        visible: parent.loved || hover.hovered
                        name: parent.loved ? "heart-filled" : "heart"
                        color: parent.loved ? Theme.accent
                             : heartHover.hovered ? Theme.textPrimary
                             : Theme.textFaint
                    }

                    HoverHandler { id: heartHover }
                    TapHandler {
                        onSingleTapped: root.favorites.toggle_track(row.track.id)
                    }
                }

                Text {
                    Layout.preferredWidth: 64
                    horizontalAlignment: Text.AlignRight
                    text: Format.duration(row.track.duration)
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
        running: root.loading && Theme.animated
    }

    ScrollMemory {
        flickable: view
        pageKey: root.scrollKey
    }
}
