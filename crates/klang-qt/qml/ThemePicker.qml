// Preset grid plus custom accent/background, matching what sone offers.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

ColumnLayout {
    id: root

    spacing: Theme.spaceLg

    readonly property var presets: JSON.parse(Theme.controller.preset_names())

    component Swatch: Rectangle {
        id: swatch
        required property var preset
        readonly property bool selected: Theme.controller.preset_name === preset.name

        implicitWidth: 168
        implicitHeight: 56
        radius: Theme.radiusSm
        color: preset.background
        border.color: swatch.selected ? Theme.accent
                    : hover.hovered ? Theme.border
                    : "transparent"
        border.width: swatch.selected ? 2 : 1

        HoverHandler { id: hover }
        TapHandler { onSingleTapped: Theme.controller.apply_preset(swatch.preset.name) }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.spaceSm
            spacing: Theme.spaceSm

            Rectangle {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                radius: 9
                color: swatch.preset.accent
            }

            Text {
                Layout.fillWidth: true
                text: swatch.preset.name
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                // The swatch paints the theme's own background, so its label
                // has to follow that theme rather than the active one.
                color: swatch.preset.light ? "#111111" : "#FFFFFF"
            }

            Icon {
                visible: swatch.selected
                Layout.preferredWidth: 14
                Layout.preferredHeight: 14
                name: "check"
                color: Theme.accent
            }
        }
    }

    component HexField: RowLayout {
        id: hexRow
        required property string label
        required property string value
        signal committed(string hex)

        spacing: Theme.space

        Text {
            Layout.preferredWidth: 96
            text: hexRow.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textSecondary
        }

        Rectangle {
            Layout.preferredWidth: 34
            Layout.preferredHeight: 34
            radius: Theme.radiusXs
            color: hexRow.value
            border.color: Theme.border
            border.width: 1
        }

        Rectangle {
            Layout.preferredWidth: 130
            Layout.preferredHeight: 34
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
                text: hexRow.value
                maximumLength: 7
                font.family: Theme.fontFamilyMono
                font.pixelSize: Theme.fontSize
                color: Theme.textPrimary
                selectionColor: Theme.accent
                selectedTextColor: Theme.onAccent
                onAccepted: hexRow.committed(text)
                onActiveFocusChanged: if (!activeFocus) text = hexRow.value
            }
        }
    }

    Text {
        text: "PRESETS"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm - 1
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
        color: Theme.textFaint
    }

    Flow {
        Layout.fillWidth: true
        spacing: Theme.spaceSm

        Repeater {
            model: root.presets
            Swatch { required property var modelData; preset: modelData }
        }
    }

    Text {
        Layout.topMargin: Theme.spaceSm
        text: "CUSTOM"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm - 1
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
        color: Theme.textFaint
    }

    HexField {
        label: Tr.t("Accent")
        value: Theme.controller.custom_accent
        onCommitted: (hex) => Theme.controller.apply_custom(hex, Theme.controller.custom_background)
    }

    HexField {
        label: Tr.t("Background")
        value: Theme.controller.custom_background
        onCommitted: (hex) => Theme.controller.apply_custom(Theme.controller.custom_accent, hex)
    }
}
