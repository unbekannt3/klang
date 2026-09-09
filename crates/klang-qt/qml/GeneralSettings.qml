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
                model: [
                    { code: "auto", label: Tr.t("Automatic") },
                    { code: "en",   label: Tr.t("English") },
                    { code: "de",   label: Tr.t("German") },
                ]

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
                        text: modelData.label
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
