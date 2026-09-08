// Slim overlay scrollbar, the way TIDAL draws it: invisible until the pointer
// is near, and never taking layout space.

import QtQuick
import QtQuick.Controls as QQC2
import me.unbk.klang

QQC2.ScrollBar {
    id: root

    /// Widen and brighten while the pointer is over the list, not just the bar.
    property bool listHovered: false

    policy: QQC2.ScrollBar.AsNeeded
    minimumSize: 0.04

    contentItem: Rectangle {
        implicitWidth: root.pressed ? 10 : (root.hovered || root.listHovered ? 8 : 4)
        radius: width / 2
        color: root.pressed ? Theme.textSecondary
             : root.hovered ? Theme.textMuted
             : Theme.hlStrong
        opacity: root.policy === QQC2.ScrollBar.AlwaysOn || root.active
                 || root.listHovered ? 1 : 0

        Behavior on implicitWidth {
            NumberAnimation { duration: Theme.durationFast }
        }
        Behavior on opacity {
            NumberAnimation { duration: Theme.duration }
        }
    }

    background: Item {}
}
