// Browser-source overlay: a local page OBS and Streamlabs can capture.
//
// Host and port restart the server, so both commit on Enter rather than per
// keystroke; a rejected value leaves the last working server running and
// reports through the shared error line.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

ColumnLayout {
    id: root

    required property var settings

    spacing: Theme.space

    readonly property var info: {
        try {
            return JSON.parse(root.settings.overlay_json || "{}")
        } catch (e) {
            return {}
        }
    }

    property string draftHost: "127.0.0.1"
    property string draftPort: "1420"

    function syncFromInfo() {
        root.draftHost = root.info.host || "127.0.0.1"
        if (root.info.port)
            root.draftPort = String(root.info.port)
    }

    Component.onCompleted: root.settings.refresh_overlay()
    onInfoChanged: root.syncFromInfo()

    SettingRow {
        Layout.fillWidth: true
        label: "Browser source overlay"
        description: "Serves a now-playing page for OBS and Streamlabs to capture."
        toggleMode: true
        checked: !!root.info.enabled
        onToggled: (value) => root.settings.apply_overlay_enabled(value)
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.space
        spacing: Theme.space

        SettingRow {
            Layout.fillWidth: true
            label: "Host"
            description: "An IP address to bind to. Use 0.0.0.0 to let another machine on the network capture it."

            SettingsField {
                implicitWidth: 180
                text: root.draftHost
                placeholder: "127.0.0.1"
                onCommitted: root.settings.apply_overlay_host(text)
            }
        }

        SettingRow {
            Layout.fillWidth: true
            label: "Port"

            SettingsField {
                implicitWidth: 100
                text: root.draftPort
                placeholder: "1420"
                onCommitted: root.settings.apply_overlay_port(parseInt(text, 10) || 0)
            }
        }

        SettingRow {
            Layout.fillWidth: true
            label: "Browser source URL"
            visible: !!root.info.enabled

            Text {
                text: root.info.url || ""
                font.family: Theme.fontFamilyMono
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textSecondary
            }
        }
    }
}
