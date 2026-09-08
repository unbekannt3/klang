// Scroll offsets, keyed by page.
//
// Main.qml destroys a page when navigating away and builds a fresh one when
// coming back, so the offset has to outlive the page itself.
pragma Singleton

import QtQuick

QtObject {
    property var offsets: ({})

    function save(key, offset) {
        if (key)
            offsets[key] = offset
    }

    function restore(key) {
        return key && offsets[key] !== undefined ? offsets[key] : 0
    }

    function forget(key) {
        if (key)
            delete offsets[key]
    }
}
