// A small "name this" dialog: title, one field, Cancel and Save.
//
// Shared because more than one thing needs a name — a folder, and the queue
// saved as a playlist. The caller decides what to do with the text.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

QQC2.Popup {
    id: prompt
    modal: true
    focus: true
    padding: Theme.spaceLg
    width: 320
    closePolicy: QQC2.Popup.CloseOnEscape

    property string promptTitle: ""
    property string mode: "create"
    property string targetId: ""

    background: Rectangle {
        color: Theme.elevated
        radius: Theme.radiusLg
        border.color: Theme.border
        border.width: 1
    }

    function showAt(t, mode_, targetId_, initial) {
        promptTitle = t
        mode = mode_
        targetId = targetId_
        field.text = initial
        parent = QQC2.Overlay.overlay
        x = (parent.width - width) / 2
        y = (parent.height - implicitHeight) / 3
        open()
        field.forceActiveFocus()
        field.selectAll()
    }

    /// The caller decides what the name is for; `mode` and `targetId` are
    /// carried through untouched so it can tell which prompt came back.
    signal accepted(string text, string mode, string targetId)

    function ask(title, initial) { showAt(title, "", "", initial) }

    function commit() {
        const text = field.text.trim()
        if (text.length === 0)
            return
        prompt.accepted(text, prompt.mode, prompt.targetId)
        close()
    }

    contentItem: ColumnLayout {
        spacing: Theme.space

        Text {
            text: prompt.promptTitle
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeLg
            font.weight: Font.DemiBold
            color: Theme.textPrimary
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 36
            radius: Theme.radiusSm
            color: Theme.inset
            border.color: field.activeFocus ? Theme.accent : Theme.border
            border.width: 1

            TextInput {
                id: field
                anchors.fill: parent
                anchors.leftMargin: Theme.spaceSm
                anchors.rightMargin: Theme.spaceSm
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textPrimary
                selectionColor: Theme.accent
                selectedTextColor: Theme.onAccent
                onAccepted: prompt.commit()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignRight
            spacing: Theme.spaceSm

            Rectangle {
                implicitWidth: 68
                implicitHeight: 32
                radius: Theme.radiusSm
                color: cancelHover.hovered ? Theme.hlFaint : "transparent"
                border.color: Theme.border
                border.width: 1

                HoverHandler { id: cancelHover }
                TapHandler { onSingleTapped: prompt.close() }

                Text {
                    anchors.centerIn: parent
                    text: Tr.t("Cancel")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textSecondary
                }
            }

            Rectangle {
                implicitWidth: 68
                implicitHeight: 32
                radius: Theme.radiusSm
                opacity: field.text.trim().length > 0 ? 1 : 0.4
                color: saveHover.hovered ? Theme.accentHover : Theme.accent

                HoverHandler { id: saveHover; enabled: field.text.trim().length > 0 }
                TapHandler { enabled: field.text.trim().length > 0; onSingleTapped: prompt.commit() }

                Text {
                    anchors.centerIn: parent
                    text: Tr.t("Save")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    font.weight: Font.DemiBold
                    color: Theme.onAccent
                }
            }
        }
    }
    }
