// Language and window behaviour. klang has neither an update-check nor a
// window-decoration toggle.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

ColumnLayout {
    id: root

    required property var settings

    spacing: Theme.space

    SettingRow {
        Layout.fillWidth: true
        label: Tr.t("Language")
        description: Tr.t("Automatic follows the system locale.")

        Row {
            spacing: Theme.spaceSm

            Repeater {
                // Driven by Tr's own list, so a new language shows up here
                // as soon as its catalogue is registered.
                model: Tr.languages

                Rectangle {
                    required property var modelData
                    readonly property bool active: root.settings.language === modelData.code

                    implicitWidth: languageLabel.implicitWidth + Theme.space
                    implicitHeight: 32
                    radius: Theme.radiusSm
                    color: active ? Theme.hlMed : hover.hovered ? Theme.hlFaint : "transparent"
                    border.color: active ? Theme.accent : Theme.border
                    border.width: 1

                    HoverHandler { id: hover }
                    TapHandler { onSingleTapped: root.settings.apply_language(modelData.code) }

                    Text {
                        id: languageLabel
                        anchors.centerIn: parent
                        text: Tr.t(modelData.label)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        color: parent.active ? Theme.textPrimary : Theme.textSecondary
                    }
                }
            }
        }
    }

    SettingRow {
        Layout.fillWidth: true
        label: Tr.t("Close to tray")
        description: Tr.t("Minimize to the system tray instead of quitting when the window is closed.")
        toggleMode: true
        checked: root.settings.minimize_to_tray
        onToggled: (value) => root.settings.apply_minimize_to_tray(value)
    }
}
