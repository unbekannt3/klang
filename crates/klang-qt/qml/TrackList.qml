// Shared track list. Every page that shows tracks uses this, so swapping the
// JSON model for a real QAbstractListModel later is a change in one file.

import QtQuick
import QtQuick.Controls as QQC2
import me.unbk.klang

Item {
    id: root

    /// JSON string or array of row objects; see klang-qt's rows.rs.
    property var tracks: []
    property string emptyText: Tr.t("Nothing here")
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
    /// tidal.com puts a block control in the row on mix pages only, where
    /// keeping a track out of future mixes is the point.
    property bool showBlock: false

    /// A queue-next control in the row, and the row's controls shown at rest
    /// rather than on hover — how tidal.com renders a suggestion list.
    property bool showQueueAdd: false
    property bool pinnedActions: false

    signal queueNextRequested(int index)

    /// Collections know when a track was added; a catalogue listing does not.
    property bool showDateAdded: false

    property string sortColumn: ""
    property bool sortDescending: true

    /// Page header scrolled above the rows. Pages pass their own so the whole
    /// page scrolls as one list — a page-level Flickable around this would
    /// have to size the list to its full content, which defeats delegate
    /// recycling and builds every row up front.
    property Component pageHeader: null

    /// Anything the page shows below the rows — credits, carousels — so it
    /// scrolls with them instead of forcing a second scroller.
    property Component pageFooter: null

    /// Emitted while the view approaches the last rows, for pages that page
    /// through their source. Repeats until the page arrives; the bridge is
    /// what guards against overlapping requests.
    signal endReached()

    signal trackActivated(int index)
    signal contextRequested(int index, real x, real y)
    /// Emitted when a sortable header is clicked; the page re-fetches.
    signal sortRequested(string column)

    /// The artist and album cells are links, as on tidal.com. A page that
    /// leaves these unconnected still gets plain text — `linked` below.
    signal artistActivated(int artistId)
    signal albumActivated(int albumId)

    /// One cell of a row that navigates somewhere. Plain text when it has
    /// nowhere to go, so a row without an id looks like what it is.
    ///
    /// `links` carries one entry per destination — a track credits several
    /// artists and each is its own link, as on tidal.com. They render as one
    /// elidable line, so only the hovered one underlines.
    component LinkCell: Item {
        id: cell
        property string text: ""
        /// [{ id, name }]; takes precedence over `text` when non-empty.
        property var links: []
        property string scheme: "artist"
        property bool linked: false
        /// Carries the id of whichever link was used.
        signal activated(int id)
        signal peeked(int id)
        signal unpeeked()

        readonly property bool multi: !!cell.links && cell.links.length > 0

        function plain(text) {
            return String(text).replace(/&/g, "&amp;")
                               .replace(/</g, "&lt;")
                               .replace(/>/g, "&gt;")
        }

        function idOf(link) {
            return link ? parseInt(link.split(":")[1]) : 0
        }

        readonly property string markup: {
            if (!cell.multi)
                return cell.plain(cell.text)
            return cell.links.map((entry) => {
                const target = cell.scheme + ":" + entry.id
                const name = cell.plain(entry.name)
                const body = target === label.hoveredLink ? "<u>" + name + "</u>" : name
                return entry.id ? '<a href="' + target + '">' + body + "</a>" : name
            }).join(", ")
        }

        implicitHeight: label.implicitHeight

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            text: cell.markup
            textFormat: Text.StyledText
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.underline: !cell.multi && cell.linked && cellHover.hovered
            color: !cell.multi && cell.linked && cellHover.hovered
                   ? Theme.textPrimary : Theme.textMuted
            linkColor: Theme.textPrimary

            onLinkActivated: (link) => cell.activated(cell.idOf(link))
            onHoveredLinkChanged: hoveredLink.length > 0
                                  ? cell.peeked(cell.idOf(hoveredLink))
                                  : cell.unpeeked()
        }

        HoverHandler {
            id: cellHover
            enabled: cell.linked || cell.multi
            cursorShape: label.hoveredLink.length > 0 || (cell.linked && !cell.multi)
                         ? Qt.PointingHandCursor : Qt.ArrowCursor
            onHoveredChanged: if (!hovered) cell.unpeeked()
        }

        TapHandler {
            enabled: cell.linked && !cell.multi
            onSingleTapped: cell.activated(0)
        }

        QQC2.ToolTip {
            // The columns elide, so the tooltip is where the full name lives.
            visible: cellHover.hovered && label.truncated
            delay: 400
            text: cell.multi ? cell.links.map((e) => e.name).join(", ") : cell.text
        }
    }

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
    // tidal.com's columns abut, with their own padding; a wide gap here
    // would cost the title and album columns their room.
    readonly property int columnGap: Theme.spaceSm

    /// Fixed widths, and the flex bases tidal.com uses for the three
    /// columns that grow: its own table is `flex: 1 0 282px` for the title,
    /// `1 1 170px` for the artist and `1 1 112px` for the album.
    ///
    /// `min` is the width below which a column stops being worth showing and
    /// `drop` orders what goes first when the list is too narrow for all of
    /// them; drop 0 stays whatever happens.
    readonly property var columnSpec: [
        { name: "number",  width: 42, basis: 0,   min: 0,   shown: root.numbered, drop: 0 },
        { name: "cover",   width: Theme.coverThumb, basis: 0, min: 0, shown: root.showCovers, drop: 0 },
        { name: "title",   width: 0,  basis: 282, min: 150, shown: true, drop: 0 },
        { name: "artist",  width: 0,  basis: 170, min: 100, shown: root.showArtist, drop: 0 },
        { name: "album",   width: 0,  basis: 112, min: 96,  shown: root.showAlbum, drop: 2 },
        { name: "added",   width: 96, basis: 0,   min: 0,   shown: root.showDateAdded, drop: 1 },
        { name: "quality", width: 56, basis: 0,   min: 0,   shown: true, drop: 5 },
        { name: "length",  width: 66, basis: 0,   min: 0,   shown: true, drop: 0 },
        { name: "bpm",     width: 52, basis: 0,   min: 0,   shown: root.showBpm, drop: 3 },
        { name: "key",     width: 48, basis: 0,   min: 0,   shown: root.showKey, drop: 4 },
        { name: "queue",   width: 24, basis: 0,   min: 0,   shown: root.showQueueAdd, drop: 0 },
        { name: "block",   width: 24, basis: 0,   min: 0,   shown: root.showBlock && root.favorites !== null, drop: 0 },
        { name: "heart",   width: 24, basis: 0,   min: 0,   shown: root.favorites !== null, drop: 0 },
    ]

    /// The last resort, once everything droppable is gone.
    readonly property int columnFloor: 64

    /// Left edge and width of every shown column, in list-local coordinates.
    /// A column a narrow list cannot fit is absent rather than squeezed, so
    /// nothing ever runs off the right edge.
    readonly property var columns: {
        const room = root.width - root.rowInset * 2 - Theme.spaceSm
        const least = (c) => c.width > 0 ? c.width : c.min
        const fits = (cols) => cols.reduce((sum, c) => sum + least(c), 0)
                             + root.columnGap * (cols.length - 1) <= room

        let shown = root.columnSpec.filter((c) => c.shown)
        const droppable = shown.filter((c) => c.drop > 0)
                               .sort((a, b) => a.drop - b.drop)
        for (const column of droppable) {
            if (fits(shown))
                break
            shown = shown.filter((c) => c !== column)
        }

        // What is left over for the columns that grow, after the fixed ones
        // and the gaps. Surplus is split evenly, as tidal.com splits it; a
        // shortfall is taken proportionally, so the widest column gives up
        // the most instead of the narrowest collapsing.
        let pool = shown.filter((c) => c.width === 0)
        let space = room - root.columnGap * (shown.length - 1)
                  - shown.reduce((sum, c) => sum + c.width, 0)
        const width = {}
        while (pool.length > 0) {
            const basis = pool.reduce((sum, c) => sum + c.basis, 0)
            const delta = space - basis
            const share = (c) => delta >= 0
                ? c.basis + Math.floor(delta / pool.length)
                : c.basis + Math.floor(delta * c.basis / basis)
            const starved = pool.filter((c) => share(c) < root.columnFloor)
            if (starved.length === 0) {
                for (const c of pool)
                    width[c.name] = share(c)
                break
            }
            for (const c of starved) {
                width[c.name] = root.columnFloor
                space -= root.columnFloor
            }
            pool = pool.filter((c) => starved.indexOf(c) < 0)
        }

        const out = {}
        let x = root.rowInset
        for (const column of shown) {
            const w = column.width > 0 ? column.width : width[column.name]
            out[column.name] = { x: x, width: w }
            x += w + root.columnGap
        }
        return out
    }

    /// Where the first row starts, for overlays drawn on top of the list.
    readonly property real rowsTop: view.y + (view.headerItem ? view.headerItem.height - view.contentY : 0)
    /// The scroller itself, for a page that wants to follow its offset.
    readonly property Flickable scroller: view
    readonly property real listRowHeight: Theme.rowHeight

    function columnX(name) {
        return root.columns[name] ? root.columns[name].x : 0
    }

    function columnWidth(name) {
        return root.columns[name] ? root.columns[name].width : 0
    }

    /// Whether a column survived the width fit.
    function columnShown(name) {
        return root.columns[name] !== undefined
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

    // The page's own header, then the column labels, both scrolling with the
    // rows: the list is the page's only scroller, so its delegates recycle
    // instead of every row existing at once.
    Component {
        id: listHeader

        Column {
            width: view.width

            Loader {
                width: parent.width
                sourceComponent: root.pageHeader
            }

            Item {
                width: parent.width
                height: root.filterable ? 38 + Theme.space : 0
                visible: root.filterable

                SettingsField {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: Theme.spaceLg
                    anchors.rightMargin: Theme.spaceLg
                    height: 38
                    placeholder: Tr.t("Filter by title, artist or album")
                    onTextChanged: root.filterText = text
                }
            }

            // Column header, TIDAL-style: thin uppercase labels over a
            // hairline, placed from the same column table as the rows.
            Item {
                width: parent.width
                height: 34

                Text {
                    visible: root.columnShown("number")
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
                    label: Tr.t("TITLE")
                    column: "NAME"
                }

                SortableHeading {
                    visible: root.columnShown("artist")
                    x: root.columnX("artist")
                    width: root.columnWidth("artist")
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Theme.spaceSm
                    label: Tr.t("ARTIST")
                    column: "ARTIST"
                }

                SortableHeading {
                    visible: root.columnShown("album")
                    x: root.columnX("album")
                    width: root.columnWidth("album")
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Theme.spaceSm
                    label: Tr.t("ALBUM")
                    column: "ALBUM"
                }

                SortableHeading {
                    visible: root.columnShown("added")
                    x: root.columnX("added")
                    width: root.columnWidth("added")
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Theme.spaceSm
                    label: Tr.t("ADDED")
                    column: "DATE"
                }

                Text {
                    visible: root.columnShown("bpm")
                    x: root.columnX("bpm")
                    width: root.columnWidth("bpm")
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Theme.spaceSm
                    horizontalAlignment: Text.AlignRight
                    text: Tr.t("BPM")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm - 1
                    font.letterSpacing: 1
                    color: Theme.textFaint
                }

                Text {
                    visible: root.columnShown("key")
                    x: root.columnX("key")
                    width: root.columnWidth("key")
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Theme.spaceSm
                    horizontalAlignment: Text.AlignRight
                    text: Tr.t("KEY")
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
                    label: Tr.t("LENGTH")
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
        }
    }

    ListView {
        id: view
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        bottomMargin: Theme.contentBottomInset
        clip: true
        model: root.visibleRows()
        header: listHeader
        footer: root.pageFooter
        // Enough rows off-screen that a flick does not tear.
        cacheBuffer: Theme.rowHeight * 8

        onContentYChanged: {
            if (contentHeight <= height)
                return
            if (contentY + height > contentHeight - Theme.rowHeight * 8)
                root.endReached()
        }
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
            /// TIDAL keeps a track it cannot stream in the list, greyed out.
            readonly property bool playable: row.track.playable !== false

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

            HoverHandler { id: hover; enabled: row.playable }
            TapHandler {
                enabled: row.playable
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
                visible: root.columnShown("number")
                x: root.columnX("number")
                width: root.columnWidth("number")
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: row.active ? "▶" : (row.position + 1)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                color: !row.playable ? Theme.textDisabled
                     : row.active ? Theme.accent
                     : Theme.textFaint
            }

            CoverArt {
                visible: root.columnShown("cover")
                x: root.columnX("cover")
                width: root.columnWidth("cover")
                height: width
                anchors.verticalCenter: parent.verticalCenter
                uuid: row.track.cover || ""
                opacity: row.playable ? 1 : 0.4

                // The bars tidal.com puts on the thumbnail of whatever is
                // playing, so the row reads as current at a glance.
                Rectangle {
                    anchors.fill: parent
                    visible: row.active
                    color: Theme.scrim

                    // Not a Row: a positioner ignores vertical anchors on its
                    // children, and these have to stay centred while they grow.
                    Item {
                        anchors.centerIn: parent
                        width: 10
                        height: 14

                        Repeater {
                            model: 3

                            Rectangle {
                                required property int index
                                x: index * 4
                                anchors.verticalCenter: parent.verticalCenter
                                width: 2
                                height: 5
                                radius: 1
                                color: Theme.accent

                                SequentialAnimation on height {
                                    running: row.active && Theme.animated
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: index * 110 }
                                    NumberAnimation {
                                        to: 14
                                        duration: 240
                                        easing.type: Easing.InOutSine
                                    }
                                    NumberAnimation {
                                        to: 5
                                        duration: 240
                                        easing.type: Easing.InOutSine
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Row {
                x: root.columnX("title")
                width: root.columnWidth("title")
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spaceXs

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth,
                                    parent.width - (badge.visible ? badge.width + Theme.spaceXs : 0))
                    text: row.track.title
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: !row.playable ? Theme.textDisabled
                         : row.active ? Theme.accent
                         : Theme.textPrimary
                }

                // TIDAL's own marker, right of the title.
                Rectangle {
                    id: badge
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!row.track.explicit
                    width: 14
                    height: 14
                    radius: 3
                    color: Theme.hlStrong

                    Text {
                        anchors.centerIn: parent
                        text: "E"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm - 2
                        font.weight: Font.Bold
                        color: Theme.textSecondary
                    }
                }
            }

            // Artist and album are their own columns, as on tidal.com,
            // rather than one subtitle line under the title.
            LinkCell {
                id: artistCell
                visible: root.columnShown("artist")
                x: root.columnX("artist")
                width: root.columnWidth("artist")
                anchors.verticalCenter: parent.verticalCenter
                text: row.track.artist
                links: row.track.artists || []
                linked: !!row.track.artistId
                onActivated: (id) => root.artistActivated(id || row.track.artistId)
                // Resting on the name brings up the card, as on tidal.com.
                onPeeked: (id) => {
                    const p = artistCell.mapToItem(null, artistCell.width / 2,
                                                   artistCell.height)
                    ArtistPeek.open(id || row.track.artistId, p)
                }
                onUnpeeked: ArtistPeek.close()
            }

            Text {
                visible: root.columnShown("added")
                x: root.columnX("added")
                width: root.columnWidth("added")
                anchors.verticalCenter: parent.verticalCenter
                text: Format.added(row.track.dateAdded)
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textMuted
            }

            LinkCell {
                visible: root.columnShown("album")
                x: root.columnX("album")
                width: root.columnWidth("album")
                anchors.verticalCenter: parent.verticalCenter
                text: row.track.album || ""
                scheme: "album"
                linked: !!row.track.albumId
                onActivated: root.albumActivated(row.track.albumId)
            }

            // Quality badge, only when the API told us something.
            Rectangle {
                readonly property bool hiRes: row.track.quality === "HI_RES_LOSSLESS"
                                           || row.track.quality === "HI_RES"

                visible: root.columnShown("quality") && !!row.track.quality
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
                visible: root.columnShown("bpm")
                x: root.columnX("bpm")
                width: root.columnWidth("bpm")
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: row.track.bpm ? row.track.bpm : "–"
                font.family: Theme.fontFamilyMono
                font.pixelSize: Theme.fontSizeSm
                color: row.track.bpm ? Theme.textSecondary : Theme.textDisabled
            }

            Item {
                visible: root.columnShown("key")
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
                    font.family: Theme.fontFamilyMono
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textDisabled
                }
            }

            Item {
                visible: root.columnShown("queue")
                x: root.columnX("queue")
                width: root.columnWidth("queue")
                height: 24
                anchors.verticalCenter: parent.verticalCenter

                Icon {
                    anchors.centerIn: parent
                    width: 17
                    height: 17
                    visible: root.pinnedActions || hover.hovered
                    name: "queue"
                    color: queueHover.hovered ? Theme.textPrimary : Theme.textFaint
                }

                HoverHandler { id: queueHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onSingleTapped: root.queueNextRequested(row.position) }
            }

            // Blocking keeps a track out of future mixes; on a mix page that
            // is a first-class action rather than a context-menu entry.
            Item {
                id: blockCell
                visible: root.columnShown("block")
                x: root.columnX("block")
                width: root.columnWidth("block")
                height: 24
                anchors.verticalCenter: parent.verticalCenter

                readonly property bool blocked: root.favorites
                    && root.favorites.revision >= 0
                    && root.favorites.is_blocked("track", row.track.id)

                Icon {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    visible: blockCell.blocked || hover.hovered
                    name: "block"
                    color: blockCell.blocked ? Theme.error
                         : blockHover.hovered ? Theme.textPrimary
                         : Theme.textFaint
                }

                HoverHandler { id: blockHover }
                TapHandler {
                    onSingleTapped: root.favorites.toggle_block("track", row.track.id)
                }
            }

            // The heart shows on hover, or always once favourited.
            Item {
                id: heartCell
                visible: root.columnShown("heart")
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
                    visible: heartCell.loved || hover.hovered || root.pinnedActions
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
                font.family: Theme.fontFamilyMono
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textFaint
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: view.count === 0 && !root.loading && root.emptyText.length > 0
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
