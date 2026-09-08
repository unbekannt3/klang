// MCP server: lets an AI client drive playback and read the library.
//
// The URL and token only exist while the server is running, so both are read
// back from the bridge after every change rather than predicted here.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

ColumnLayout {
    id: root

    required property var settings

    spacing: Theme.space

    readonly property var info: {
        try {
            return JSON.parse(root.settings.mcp_json || "{}")
        } catch (e) {
            return {}
        }
    }

    property bool tokenVisible: false

    Component.onCompleted: root.settings.refresh_mcp()

    SettingRow {
        Layout.fillWidth: true
        label: "MCP server"
        description: "Exposes playback, the queue and your library to MCP clients on this machine."
        toggleMode: true
        checked: !!root.info.enabled
        onToggled: (value) => root.settings.apply_mcp_enabled(value)
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.space
        spacing: Theme.space
        visible: !!root.info.enabled

        SettingRow {
            Layout.fillWidth: true
            label: "Endpoint"

            Text {
                text: root.info.url || ""
                font.family: Theme.fontFamilyMono
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textSecondary
            }
        }

        SettingRow {
            Layout.fillWidth: true
            label: "Token"
            description: "Clients authenticate with this. Regenerating it disconnects anything already connected."

            RowLayout {
                spacing: Theme.spaceSm

                Text {
                    text: root.tokenVisible ? (root.info.token || "")
                                            : "••••••••••••••••"
                    font.family: Theme.fontFamilyMono
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textSecondary
                }

                SettingsButton {
                    label: root.tokenVisible ? "Hide" : "Show"
                    onClicked: root.tokenVisible = !root.tokenVisible
                }

                SettingsButton {
                    label: "Regenerate"
                    onClicked: root.settings.regenerate_mcp_token()
                }
            }
        }
    }
}
