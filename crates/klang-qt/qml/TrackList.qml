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

    // One column table drives both the header and the rows. A RowLayout was
    // not enough: it splits surplus space evenly between fillWidth items
    // regardless of their preferred sizes, and the two ended up disagreeing.
    readonly property int rowInset: Theme.spaceLg + Theme.spaceSm
    readonly property int columnGap: Theme.space

    readonly property var columnSpec: [
        { name: "number",  width: 28, shown: root.numbered },
        { name: "cover",   width: Theme.coverThumb, shown: root.showCovers },
        { name: "title",   width: 0,  shown: true },
        { name: "artist",  width: 0,  shown: root.showArtist },
        { name: "album",   width: 0,  shown: root.showAlbum },
        { name: "quality", width: 56, shown: true },
        { name: "bpm",     width: 52, shown: root.showBpm },
        { name: "key",     width: 48, shown: root.showKey },
        { name: "heart",   width: 24, shown: root.favorites !== null },
        { name: "length",  width: 64, shown: true },
    ]

    /// Left edge and width of every shown column, in row-local coordinates.
    readonly property var columns: {
        const shown = root.columnSpec.filter((c) => c.shown)
        const flexible = shown.filter((c) => c.width === 0)
        const fixed = shown.reduce((sum, c) => sum + c.width, 0)
        const available = root.width - root.rowInset * 2 - Theme.spaceSm
                        - fixed - root.columnGap * (shown.length - 1)
        // Roughly tidal.com's proportions between title, artist and album.
        const share = { title: 0.44, artist: 0.28, album: 0.28 }
        const total = flexible.reduce((sum, c) => sum + share[c.name], 0) || 1
        const free = Math.max(120, available)

        const out = {}
        let x = root.rowInset
        for (const column of shown) {
            const width = column.width > 0
                ? column.width
                : Math.round(free * share[column.name] / total)
            out[column.name] = { x: x, width: width }
            x += width + root.columnGap
        }
        return out
    }

    function columnX(name) {
        return root.columns[name] ? root.columns[name].x : 0
    }

    function columnWidth(name) {
        return root.columns[name] ? root.columns[name].width : 0
    }

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

    // Column header, TIDAL-style: thin uppercase labels over a hairline. It
    // sits outside the ListView so it keeps a row's exact geometry — and so
    // it stays put while the list scrolls.
    Item {
        id: columnHeader
        anchors.top: root.filterable ? filterField.bottom : parent.top
        anchors.topMargin: root.filterable ? Theme.space : 0
        anchors.left: parent.left
        anchors.right: parent.right
        height: 34

        Text {
            visible: root.numbered
            x: root.columnX("number")
            width: root.columnWidth("number")
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.spaceSm
            horizontalAlignment: Text.AlignRight
            text: "#"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm - 1
            font.letterSpacing: 1
            color: Theme.textFaint
        }

        SortableHeading {
            x: root.columnX("title")
            width: root.columnWidth("title")
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.spaceSm
            label: "TITLE"
            column: "NAME"
        }

        SortableHeading {
            visible: root.showArtist
            x: root.columnX("artist")
            width: root.columnWidth("artist")
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.spaceSm
            label: "ARTIST"
            column: "ARTIST"
        }

        SortableHeading {
            visible: root.showAlbum
            x: root.columnX("album")
            width: root.columnWidth("album")
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.spaceSm
            label: "ALBUM"
            column: "ALBUM"
        }

        Text {
            visible: root.showBpm
            x: root.columnX("bpm")
            width: root.columnWidth("bpm")
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.spaceSm
            horizontalAlignment: Text.AlignRight
            text: "BPM"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm - 1
            font.letterSpacing: 1
            color: Theme.textFaint
        }

        Text {
            visible: root.showKey
            x: root.columnX("key")
            width: root.columnWidth("key")
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.spaceSm
            horizontalAlignment: Text.AlignRight
            text: "KEY"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm - 1
            font.letterSpacing: 1
            color: Theme.textFaint
        }

        SortableHeading {
            x: root.columnX("length")
            width: root.columnWidth("length")
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.spaceSm
            label: "LENGTH"
            column: "DURATION"
            alignment: Text.AlignRight
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

    ListView {
        id: view
        anchors.top: columnHeader.bottom
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

        delegate: Rectangle {
            id: row
            required property var modelData
            /// The row's track, and where it sits in the unfiltered list.
            readonly property var track: modelData.row
            readonly property int position: modelData.position

            readonly property bool active: track.id === root.activeId

            width: view.width
            height: Theme.rowHeight
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: Theme.spaceLg
                anchors.rightMargin: Theme.spaceLg
                radius: Theme.radiusXs
                color: hover.hovered ? Theme.hlFaint : "transparent"
            }

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

            Text {
                visible: root.numbered
                x: root.columnX("number")
                width: root.columnWidth("number")
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: row.active ? "▶" : (row.position + 1)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                color: row.active ? Theme.accent : Theme.textFaint
            }

            CoverArt {
                visible: root.showCovers
                x: root.columnX("cover")
                width: root.columnWidth("cover")
                height: width
                anchors.verticalCenter: parent.verticalCenter
                uuid: row.track.cover || ""
            }

            Text {
                x: root.columnX("title")
                width: root.columnWidth("title")
                anchors.verticalCenter: parent.verticalCenter
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
                x: root.columnX("artist")
                width: root.columnWidth("artist")
                anchors.verticalCenter: parent.verticalCenter
                text: row.track.artist
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                color: Theme.textMuted
            }

            Text {
                visible: root.showAlbum
                x: root.columnX("album")
                width: root.columnWidth("album")
                anchors.verticalCenter: parent.verticalCenter
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
                x: root.columnX("quality")
                     + (root.columnWidth("quality") - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                width: qualityText.implicitWidth + Theme.spaceSm
                height: 18
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
                x: root.columnX("bpm")
                width: root.columnWidth("bpm")
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: row.track.bpm ? row.track.bpm : "–"
                font.family: Theme.monoFamily
                font.pixelSize: Theme.fontSizeSm
                color: row.track.bpm ? Theme.textSecondary : Theme.textDisabled
            }

            Item {
                visible: root.showKey
                x: root.columnX("key")
                width: root.columnWidth("key")
                height: 20
                anchors.verticalCenter: parent.verticalCenter

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
                id: heartCell
                visible: root.favorites !== null
                x: root.columnX("heart")
                width: root.columnWidth("heart")
                height: 24
                anchors.verticalCenter: parent.verticalCenter

                readonly property bool loved: root.favorites
                    && root.favorites.revision >= 0
                    && root.favorites.is_track(row.track.id)

                Icon {
                    anchors.centerIn: parent
                    width: 17
                    height: 17
                    visible: heartCell.loved || hover.hovered
                    name: heartCell.loved ? "heart-filled" : "heart"
                    color: heartCell.loved ? Theme.accent
                         : heartHover.hovered ? Theme.textPrimary
                         : Theme.textFaint
                }

                HoverHandler { id: heartHover }
                TapHandler {
                    onSingleTapped: root.favorites.toggle_track(row.track.id)
                }
            }

            Text {
                x: root.columnX("length")
                width: root.columnWidth("length")
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: Format.duration(row.track.duration)
                font.family: Theme.monoFamily
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textFaint
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
