// Restores a Flickable to where the same page was left, and saves the offset
// again when the page goes away.
//
// The restore cannot happen on completion: the list is still empty then, and
// setting contentY past an empty view's bounds clamps it back to zero. It is
// retried as content arrives instead, and stops at the first success so a
// later load does not yank the view out from under the reader.

import QtQuick
import me.unbk.klang

Item {
    id: root

    required property Flickable flickable
    /// Stable per destination, e.g. "album:12345". Empty disables memory.
    required property string pageKey

    property bool restored: false

    function tryRestore() {
        if (restored || !flickable || pageKey.length === 0)
            return
        const offset = ScrollStore.restore(pageKey)
        if (offset <= 0) {
            restored = true
            return
        }
        if (flickable.contentHeight < offset + flickable.height)
            return
        flickable.contentY = offset
        restored = true
    }

    onPageKeyChanged: restored = false

    Component.onCompleted: tryRestore()
    Component.onDestruction: {
        if (flickable && pageKey.length > 0)
            ScrollStore.save(pageKey, flickable.contentY)
    }

    Connections {
        target: root.flickable
        function onContentHeightChanged() { root.tryRestore() }
    }
}
