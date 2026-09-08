// Outbound HTTP/SOCKS5 proxy for the TIDAL API and scrobble providers.
//
// Text fields hold a local draft; only Enter (or blur after Enter) commits it
// with apply_proxy_json, the same "commit, don't sync every keystroke"
// pattern ThemePicker's HexField uses for hex input. The toggle and proxy
// type are single-tap choices, so those commit immediately.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

ColumnLayout {
    id: root

    required property var settings

    spacing: Theme.space

    property bool draftEnabled: false
    property string draftType: "http"
    property string draftHost: ""
    property string draftPort: "1080"
    property string draftUsername: ""
    property string draftPassword: ""

    function syncFromSettings() {
        let p = {}
        try { p = JSON.parse(root.settings.proxy_json || "{}") } catch (e) { p = {} }
        root.draftEnabled = !!p.enabled
        root.draftType = p.proxy_type || "http"
        root.draftHost = p.host || ""
        root.draftPort = String(p.port || 1080)
        root.draftUsername = p.username || ""
        root.draftPassword = p.password || ""
    }

    function commit() {
        root.settings.apply_proxy_json(JSON.stringify({
            enabled: root.draftEnabled,
            proxy_type: root.draftType,
            host: root.draftHost,
            port: parseInt(root.draftPort, 10) || 0,
            username: root.draftUsername.length > 0 ? root.draftUsername : null,
            password: root.draftPassword.length > 0 ? root.draftPassword : null,
        }))
    }

    Component.onCompleted: root.syncFromSettings()
    Connections {
        target: root.settings
        function onProxy_jsonChanged() { root.syncFromSettings() }
    }

    component Pill: Rectangle {
        id: pill
        required property string label
        property bool active: false
        signal clicked()

        implicitWidth: pillText.implicitWidth + Theme.space
        implicitHeight: 32
        radius: Theme.radiusSm
        color: pill.active ? Theme.hlMed : hover.hovered ? Theme.hlFaint : "transparent"
        border.color: pill.active ? Theme.accent : Theme.border
        border.width: 1

        HoverHandler { id: hover }
        TapHandler { onSingleTapped: pill.clicked() }

        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            color: pill.active ? Theme.textPrimary : Theme.textSecondary
        }
    }

    component Field: Rectangle {
        id: field
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
            echoMode: field.isPassword ? TextInput.Password : TextInput.Normal
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textPrimary
            selectionColor: Theme.accent
            selectedTextColor: Theme.onAccent
            onAccepted: field.committed()

            Text {
                visible: input.text.length === 0
                text: field.placeholder
                font: input.font
                color: Theme.textFaint
            }
        }
    }

    SettingRow {
        Layout.fillWidth: true
        label: "Use a proxy"
        description: "Routes TIDAL API and scrobble traffic through the proxy below."
        toggleMode: true
        checked: root.draftEnabled
        onToggled: (value) => { root.draftEnabled = value; root.commit() }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.space
        spacing: Theme.space
        enabled: root.draftEnabled
        opacity: root.draftEnabled ? 1 : 0.5

        SettingRow {
            Layout.fillWidth: true
            label: "Proxy type"

            Row {
                spacing: Theme.spaceSm
                Pill {
                    label: "HTTP"
                    active: root.draftType === "http"
                    onClicked: { root.draftType = "http"; root.commit() }
                }
                Pill {
                    label: "SOCKS5"
                    active: root.draftType === "socks5"
                    onClicked: { root.draftType = "socks5"; root.commit() }
                }
            }
        }

        SettingRow {
            Layout.fillWidth: true
            label: "Host and port"

            RowLayout {
                spacing: Theme.spaceSm
                Field {
                    implicitWidth: 180
                    placeholder: "proxy.example.com"
                    text: root.draftHost
                    onTextChanged: root.draftHost = text
                    onCommitted: root.commit()
                }
                Field {
                    implicitWidth: 70
                    placeholder: "1080"
                    text: root.draftPort
                    onTextChanged: root.draftPort = text
                    onCommitted: root.commit()
                }
            }
        }

        SettingRow {
            Layout.fillWidth: true
            label: "Credentials"
            description: "Optional — leave blank if the proxy needs none."

            RowLayout {
                spacing: Theme.spaceSm
                Field {
                    implicitWidth: 140
                    placeholder: "Username"
                    text: root.draftUsername
                    onTextChanged: root.draftUsername = text
                    onCommitted: root.commit()
                }
                Field {
                    implicitWidth: 140
                    isPassword: true
                    placeholder: "Password"
                    text: root.draftPassword
                    onTextChanged: root.draftPassword = text
                    onCommitted: root.commit()
                }
            }
        }

        SettingRow {
            Layout.fillWidth: true
            label: "Connection test"
            description: root.settings.proxy_testing ? "Testing…" : root.settings.proxy_test_result

            Rectangle {
                id: testBtn
                implicitWidth: testText.implicitWidth + Theme.space
                implicitHeight: 32
                radius: Theme.radiusSm
                opacity: root.settings.proxy_testing ? 0.5 : 1
                color: hover.hovered ? Theme.hlFaint : "transparent"
                border.color: Theme.border
                border.width: 1

                HoverHandler { id: hover; enabled: !root.settings.proxy_testing }
                TapHandler {
                    enabled: !root.settings.proxy_testing
                    onSingleTapped: root.settings.test_proxy(JSON.stringify({
                        enabled: true,
                        proxy_type: root.draftType,
                        host: root.draftHost,
                        port: parseInt(root.draftPort, 10) || 0,
                        username: root.draftUsername.length > 0 ? root.draftUsername : null,
                        password: root.draftPassword.length > 0 ? root.draftPassword : null,
                    }))
                }

                Text {
                    id: testText
                    anchors.centerIn: parent
                    text: "Test connection"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textSecondary
                }
            }
        }
    }
}
