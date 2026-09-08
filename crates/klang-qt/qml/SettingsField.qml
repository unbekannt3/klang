// Single-line text input for the settings pages.
//
// The draft lives in the caller; this only reports Enter through
// `committed`, so a half-typed host or port never reaches the bridge.

import QtQuick
import me.unbk.klang

Rectangle {
    id: root

    property alias text: input.text
    property bool isPassword: false
    property string placeholder: ""
    signal committed()

    implicitHeight: 32
    radius: Theme.radiusXs
    color: Theme.inset
    border.color: input.activeFocus ? Theme.accent : Theme.border
    border.width: 1

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: Theme.spaceSm
        anchors.rightMargin: Theme.spaceSm
        verticalAlignment: TextInput.AlignVCenter
        echoMode: root.isPassword ? TextInput.Password : TextInput.Normal
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        color: Theme.textPrimary
        selectionColor: Theme.accent
        selectedTextColor: Theme.onAccent
        onAccepted: root.committed()

        Text {
            visible: input.text.length === 0
            text: root.placeholder
            font: input.font
            color: Theme.textFaint
        }
    }
}
