// Resize grips for a frameless window. A client cannot move or resize itself on
// Wayland, so both go through the compositor via QWindow's startSystemResize.

import QtQuick

Item {
    id: root

    required property var window
    /// Grab area around the window edge.
    property int margin: 6

    anchors.fill: parent
    z: 9999

    component Grip: Item {
        id: grip
        required property int edges
        required property string shape

        HoverHandler {
            cursorShape: grip.shape === "h" ? Qt.SizeHorCursor
                       : grip.shape === "v" ? Qt.SizeVerCursor
                       : grip.shape === "bd" ? Qt.SizeBDiagCursor
                       : Qt.SizeFDiagCursor
        }

        DragHandler {
            target: null
            grabPermissions: PointerHandler.CanTakeOverFromAnything
            onActiveChanged: if (active) root.window.startSystemResize(grip.edges)
        }
    }

    // Edges
    Grip {
        edges: Qt.LeftEdge; shape: "h"
        x: 0; y: root.margin; width: root.margin; height: parent.height - root.margin * 2
    }
    Grip {
        edges: Qt.RightEdge; shape: "h"
        x: parent.width - root.margin; y: root.margin
        width: root.margin; height: parent.height - root.margin * 2
    }
    Grip {
        edges: Qt.TopEdge; shape: "v"
        x: root.margin; y: 0; width: parent.width - root.margin * 2; height: root.margin
    }
    Grip {
        edges: Qt.BottomEdge; shape: "v"
        x: root.margin; y: parent.height - root.margin
        width: parent.width - root.margin * 2; height: root.margin
    }

    // Corners
    Grip {
        edges: Qt.LeftEdge | Qt.TopEdge; shape: "fd"
        x: 0; y: 0; width: root.margin; height: root.margin
    }
    Grip {
        edges: Qt.RightEdge | Qt.TopEdge; shape: "bd"
        x: parent.width - root.margin; y: 0; width: root.margin; height: root.margin
    }
    Grip {
        edges: Qt.LeftEdge | Qt.BottomEdge; shape: "bd"
        x: 0; y: parent.height - root.margin; width: root.margin; height: root.margin
    }
    Grip {
        edges: Qt.RightEdge | Qt.BottomEdge; shape: "fd"
        x: parent.width - root.margin; y: parent.height - root.margin
        width: root.margin; height: root.margin
    }
}
