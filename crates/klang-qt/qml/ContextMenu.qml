// Reusable themed popup menu, opened at a point and flipped away from
// whichever window edge it would otherwise spill past.
//
// Model item: { label, icon, danger, separator, submenu, onTriggered }. A
// separator needs only `separator: true`; `submenu` nests one more level of
// the same shape (exactly one — a submenu row's own `submenu` is ignored);
// `onTriggered` runs, and the whole menu closes, when a leaf row is picked.
// Per-item callbacks were chosen over a single `triggered(index)` signal
// because a submenu leaf has no clean single-integer index to report, and
// each caller already has the right closure (favorites.toggle_track(id),
// etc.) sitting right where the item is built.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

QQC2.Popup {
    id: root

    property var model: []
    // The top-level entry whose submenu is open, or null.
    property var openSubmenuEntry: null

    readonly property int menuWidth: 232
    readonly property int rowHeight: 36

    width: menuWidth
    padding: Theme.spaceXs
    modal: false
    focus: true
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside

    background: Rectangle {
        color: Theme.elevated
        radius: Theme.radius
        border.color: Theme.border
        border.width: 1
    }

    onClosed: {
        openSubmenuEntry = null
        submenu.close()
    }

    component MenuRow: QQC2.ItemDelegate {
        id: rowItem
        required property var entry
        // A submenu row cannot itself open a further submenu — one level only.
        property bool nested: false
        // Bound-in callbacks rather than calling `root.xxx()` directly: a
        // function *value* read out of an outer id resolves fine from a
        // nested inline component, but Qt 6 raises "root is not defined" the
        // moment that same outer id is referenced from inside a handler's
        // own statement block, so the call has to happen one scope in.
        property var requestClose: null
        property var requestSubmenu: null

        width: parent ? parent.width : root.menuWidth
        height: !!entry.separator ? Theme.spaceSm + 1 : root.rowHeight
        hoverEnabled: !entry.separator
        enabled: !entry.separator
        padding: 0

        readonly property bool danger: !!entry.danger
        readonly property color rowColor: danger && hovered ? Theme.onAccent
                                         : danger ? Theme.error
                                         : hovered ? Theme.textPrimary : Theme.textSecondary

        background: Item {
            Rectangle {
                visible: !!rowItem.entry.separator
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.spaceSm
                anchors.rightMargin: Theme.spaceSm
                height: 1
                color: Theme.border
            }
            Rectangle {
                visible: !rowItem.entry.separator
                anchors.fill: parent
                radius: Theme.radiusSm
                color: rowItem.danger && rowItem.hovered ? Theme.error
                     : rowItem.hovered ? Theme.hlFaint : "transparent"
            }
        }

        contentItem: RowLayout {
            visible: !rowItem.entry.separator
            spacing: Theme.spaceSm

            Icon {
                Layout.leftMargin: Theme.spaceSm
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                name: rowItem.entry.icon || ""
                color: rowItem.rowColor
            }

            Text {
                Layout.fillWidth: true
                text: rowItem.entry.label || ""
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                color: rowItem.rowColor
            }

            Icon {
                visible: !rowItem.nested && !!rowItem.entry.submenu
                Layout.preferredWidth: 14
                Layout.preferredHeight: 14
                Layout.rightMargin: Theme.spaceSm
                name: "forward"
                color: Theme.textFaint
            }
        }

        onClicked: {
            if (entry.separator)
                return
            if (!nested && entry.submenu && entry.submenu.length > 0) {
                if (requestSubmenu)
                    requestSubmenu(rowItem)
                return
            }
            if (entry.onTriggered)
                entry.onTriggered()
            if (requestClose)
                requestClose()
        }
    }

    component MenuList: Column {
        id: list
        required property var rows
        property bool nested: false
        width: root.availableWidth

        Repeater {
            model: list.rows
            delegate: MenuRow {
                required property var modelData
                entry: modelData
                nested: list.nested
                requestClose: root.closeAll
                requestSubmenu: root.openSubmenu
            }
        }
    }

    MenuList {
        rows: root.model
    }

    QQC2.Popup {
        id: submenu
        parent: QQC2.Overlay.overlay
        width: root.menuWidth
        padding: Theme.spaceXs
        modal: false
        focus: true
        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside

        background: Rectangle {
            color: Theme.elevated
            radius: Theme.radius
            border.color: Theme.border
            border.width: 1
        }

        contentItem: MenuList {
            rows: root.openSubmenuEntry ? root.openSubmenuEntry.submenu : []
            nested: true
        }
    }

    function openSubmenu(rowItem) {
        openSubmenuEntry = rowItem.entry
        const bounds = QQC2.Overlay.overlay
        const rightEdge = rowItem.mapToItem(bounds, rowItem.width, 0)
        const leftEdge = rowItem.mapToItem(bounds, 0, 0)
        submenu.x = rightEdge.x + submenu.width > bounds.width
                  ? leftEdge.x - submenu.width : rightEdge.x
        submenu.y = Math.min(rightEdge.y, bounds.height - submenu.implicitHeight)
        submenu.open()
    }

    function closeAll() {
        submenu.close()
        root.close()
    }

    /// Position `popup` at overlay-space (gx, gy), flipped onto whichever
    /// side keeps it fully inside the window.
    function place(popup, gx, gy) {
        const bounds = QQC2.Overlay.overlay
        popup.x = gx + popup.implicitWidth > bounds.width
                ? Math.max(0, gx - popup.implicitWidth) : gx
        popup.y = gy + popup.implicitHeight > bounds.height
                ? Math.max(0, gy - popup.implicitHeight) : gy
    }

    /// Open at `point` (an {x, y}), given in `target`'s local coordinates.
    function openAt(point, target) {
        parent = QQC2.Overlay.overlay
        const global = target.mapToItem(QQC2.Overlay.overlay, point.x, point.y)
        place(root, global.x, global.y)
        open()
    }
}
