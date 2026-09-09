// Blocks mouse input to whatever is underneath, and optionally darkens it.
// Every modal has one behind it and another inside the panel.
//
// A MouseArea, not a TapHandler: it takes hover and the wheel too, so the
// page behind a dialog neither highlights nor scrolls.

import QtQuick
import me.unbk.klang

MouseArea {
    id: root

    /// Transparent where the shield only has to block, not darken.
    property color scrim: "transparent"

    /// True on the shield that sits under a full-window overlay: it registers
    /// with OverlayStack so the page area behind stops taking input. False on
    /// the one inside a panel, which only has to keep clicks off the scrim.
    property bool blocksPage: false

    /// A click on the shield itself. The panel's shield ignores it.
    signal dismissed()

    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.AllButtons
    onClicked: root.dismissed()
    onWheel: (wheel) => wheel.accepted = true

    // Registered on visibility, not on creation: a dialog kept around hidden
    // would otherwise hold the page disabled for the whole session.
    property bool registered: false

    function syncOverlayStack() {
        const wanted = root.blocksPage && root.visible
        if (wanted === root.registered)
            return
        root.registered = wanted
        if (wanted)
            OverlayStack.push()
        else
            OverlayStack.pop()
    }

    onVisibleChanged: root.syncOverlayStack()
    onBlocksPageChanged: root.syncOverlayStack()
    Component.onCompleted: root.syncOverlayStack()
    Component.onDestruction: if (root.registered) OverlayStack.pop()

    Rectangle {
        anchors.fill: parent
        color: root.scrim
    }
}
