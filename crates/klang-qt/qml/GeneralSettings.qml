// Window behaviour. klang has neither an update-check nor a
// window-decoration toggle, so this stays a single row.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

ColumnLayout {
    id: root

    required property var settings

    spacing: Theme.space

    SettingRow {
        Layout.fillWidth: true
        label: "Close to tray"
        description: "Minimize to the system tray instead of quitting when the window is closed."
        toggleMode: true
        checked: root.settings.minimize_to_tray
        onToggled: (value) => root.settings.apply_minimize_to_tray(value)
    }
}
