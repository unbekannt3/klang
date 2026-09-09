// Labelled settings row: label + optional description on the left, a
// control on the right. Every setting on the page goes through this, so the
// toggle switch only needs to exist in one place (set toggleMode instead of
// supplying a custom control).

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

RowLayout {
    id: root

    required property string label
    property string description: ""
    property bool toggleMode: false
    property bool checked: false
    signal toggled(bool value)

    default property alias content: controlSlot.data

    Layout.fillWidth: true
    spacing: Theme.spaceLg

    component Toggle: Rectangle {
        id: sw
        property bool checked: false
        signal toggled(bool value)

        implicitWidth: 40
        implicitHeight: 22
        radius: height / 2
        opacity: sw.enabled ? 1 : 0.5
        color: sw.checked ? Theme.accent : Theme.hlMed
        // Off, the fill barely clears the surface; the outline carries it.
        border.color: Theme.borderStrong
        border.width: sw.checked ? 0 : 1

        HoverHandler { enabled: sw.enabled }
        TapHandler { enabled: sw.enabled; onSingleTapped: sw.toggled(!sw.checked) }

        Rectangle {
            width: parent.height - 6
            height: width
            radius: width / 2
            y: 3
            x: sw.checked ? parent.width - width - 3 : 3
            // Off there is no accent under it, so the accent's foreground
            // (black on dark themes) would vanish into the track.
            color: sw.checked ? Theme.onAccent : Theme.textMuted

            Behavior on x { NumberAnimation { duration: Theme.durationFast } }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Text {
            Layout.fillWidth: true
            text: root.label
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: root.enabled ? Theme.textPrimary : Theme.textDisabled
        }

        Text {
            Layout.fillWidth: true
            visible: root.description.length > 0
            text: root.description
            wrapMode: Text.WordWrap
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            color: Theme.textFaint
        }
    }

    // A single Item on the right, sized to whichever half is active — keeps
    // the unused half (an invisible Toggle, or an empty slot) from reserving
    // layout space it isn't using.
    Item {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: root.toggleMode ? toggleSwitch.implicitWidth : controlSlot.implicitWidth
        implicitHeight: root.toggleMode ? toggleSwitch.implicitHeight : controlSlot.implicitHeight

        Toggle {
            id: toggleSwitch
            visible: root.toggleMode
            anchors.verticalCenter: parent.verticalCenter
            checked: root.checked
            enabled: root.enabled
            onToggled: (value) => root.toggled(value)
        }

        Item {
            id: controlSlot
            visible: !root.toggleMode
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }
    }
}
