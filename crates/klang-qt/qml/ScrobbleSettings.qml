// Last.fm, Libre.fm and ListenBrainz. The first two need a browser
// round-trip (the same shape as TIDAL's own device-code sign-in); klang has
// no web engine, so the flow is: open the auth page, the user authorizes
// there, then confirms back here. ListenBrainz just takes a user token
// pasted from the visitor's own profile page — no round-trip to drive.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

ColumnLayout {
    id: root

    required property var settings

    spacing: Theme.space

    readonly property var statuses: JSON.parse(root.settings.scrobble_status_json || "[]")

    function statusFor(name) {
        return root.statuses.find((s) => s.name === name) || { connected: false, username: null }
    }

    component ActionButton: Rectangle {
        id: btn
        required property string label
        property bool primary: false
        signal clicked()

        implicitWidth: btnText.implicitWidth + Theme.space
        implicitHeight: 32
        radius: Theme.radiusSm
        opacity: btn.enabled ? 1 : 0.5
        color: btn.primary ? (hover.hovered ? Theme.accentHover : Theme.accent)
                            : (hover.hovered ? Theme.hlFaint : "transparent")
        border.color: btn.primary ? "transparent" : Theme.border
        border.width: btn.primary ? 0 : 1

        HoverHandler { id: hover; enabled: btn.enabled }
        TapHandler { enabled: btn.enabled; onSingleTapped: btn.clicked() }

        Text {
            id: btnText
            anchors.centerIn: parent
            text: btn.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            color: btn.primary ? Theme.onAccent : Theme.textSecondary
        }
    }

    component TokenField: Rectangle {
        id: field
        property alias text: input.text
        property string placeholder: ""

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
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textPrimary
            selectionColor: Theme.accent
            selectedTextColor: Theme.onAccent

            Text {
                visible: input.text.length === 0
                text: field.placeholder
                font: input.font
                color: Theme.textFaint
            }
        }
    }

    // Last.fm and Libre.fm are identical apart from which pair of
    // scrobble.rs calls they hit, so one row type drives both.
    component AudioscrobblerRow: SettingRow {
        id: row
        required property string provider
        required property string providerLabel
        readonly property var status: root.statusFor(row.provider)
        readonly property bool pending: root.settings.scrobble_pending_provider === row.provider

        label: row.providerLabel
        description: row.status.connected
                    ? "Connected as " + row.status.username
                    : row.pending
                    ? "Authorize klang in the browser tab that just opened, then confirm below."
                    : "Not connected."

        RowLayout {
            spacing: Theme.spaceSm
            enabled: !root.settings.scrobble_busy

            ActionButton {
                visible: row.status.connected
                label: "Disconnect"
                onClicked: root.settings.disconnect_scrobbler(row.provider)
            }
            ActionButton {
                visible: !row.status.connected && !row.pending
                label: "Connect"
                primary: true
                onClicked: row.provider === "lastfm"
                           ? root.settings.connect_lastfm()
                           : root.settings.connect_librefm()
            }
            ActionButton {
                visible: row.pending
                label: "Open browser"
                onClicked: Qt.openUrlExternally(root.settings.scrobble_auth_url)
            }
            ActionButton {
                visible: row.pending
                label: "I've authorized"
                primary: true
                onClicked: root.settings.confirm_scrobble_auth()
            }
        }
    }

    AudioscrobblerRow { Layout.fillWidth: true; provider: "lastfm"; providerLabel: "Last.fm" }
    AudioscrobblerRow { Layout.fillWidth: true; provider: "librefm"; providerLabel: "Libre.fm" }

    SettingRow {
        Layout.fillWidth: true
        label: "ListenBrainz"
        description: root.statusFor("listenbrainz").connected
                    ? "Connected as " + root.statusFor("listenbrainz").username
                    : "Paste a user token from your ListenBrainz profile page."

        RowLayout {
            spacing: Theme.spaceSm
            enabled: !root.settings.scrobble_busy

            TokenField {
                id: lbToken
                visible: !root.statusFor("listenbrainz").connected
                implicitWidth: 180
                placeholder: "User token"
            }
            ActionButton {
                visible: !root.statusFor("listenbrainz").connected
                label: "Connect"
                primary: true
                enabled: lbToken.text.length > 0
                onClicked: root.settings.connect_listenbrainz(lbToken.text)
            }
            ActionButton {
                visible: root.statusFor("listenbrainz").connected
                label: "Disconnect"
                onClicked: root.settings.disconnect_scrobbler("listenbrainz")
            }
        }
    }
}
