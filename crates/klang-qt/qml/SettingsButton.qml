// Small secondary button for the settings pages.

import QtQuick
import me.unbk.klang

Rectangle {
    id: root

    required property string label
    signal clicked()

    implicitWidth: buttonText.implicitWidth + Theme.space
    implicitHeight: 30
    radius: Theme.radiusSm
    color: hover.hovered ? Theme.hlMed : "transparent"
    border.color: Theme.border
    border.width: 1

    HoverHandler { id: hover }
    TapHandler { onSingleTapped: root.clicked() }

    Text {
        id: buttonText
        anchors.centerIn: parent
        text: root.label
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        color: Theme.textSecondary
    }
}
