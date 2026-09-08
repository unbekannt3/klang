// PKCE by default: TIDAL's device-code client is restricted and its tokens do
// not grant lossless or Hi-Res. Device code stays as a fallback, labelled.
// Neither flow needs a web engine.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    required property var auth

    Rectangle {
        anchors.fill: parent
        color: Theme.base
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.spaceXl * 2, 420)
        spacing: Theme.spaceLg

        Image {
            Layout.alignment: Qt.AlignHCenter
            source: "qrc:/qt/qml/me/unbk/klang/qml/klang.png"
            sourceSize.width: 88
            sourceSize.height: 88
            Layout.preferredWidth: 88
            Layout.preferredHeight: 88
            smooth: true
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: "klang"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeDisplay
            font.weight: Font.Bold
            font.letterSpacing: 2
            color: Theme.textPrimary
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.auth.awaiting_redirect
                  ? "Sign in in your browser, then paste the address it ends on."
                  : root.auth.user_code.length > 0
                    ? "Open the address below and enter this code."
                    : "Sign in with your TIDAL account."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textMuted
        }

        // ---- PKCE: paste the redirect back --------------------------
        Rectangle {
            Layout.fillWidth: true
            visible: root.auth.awaiting_redirect
            implicitHeight: 44
            radius: Theme.radiusSm
            color: Theme.inset
            border.color: redirect.activeFocus ? Theme.accent : Theme.border
            border.width: 1

            TextInput {
                id: redirect
                anchors.fill: parent
                anchors.leftMargin: Theme.space
                anchors.rightMargin: Theme.space
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                font.family: Theme.monoFamily
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textPrimary
                selectionColor: Theme.accent
                selectedTextColor: Theme.onAccent
                onAccepted: root.auth.finish_browser_login(text)

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: !redirect.text
                    text: "https://tidal.com/android/login/auth?code=…"
                    font: redirect.font
                    color: Theme.textFaint
                    elide: Text.ElideRight
                }
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            visible: root.auth.awaiting_redirect
            implicitWidth: 160
            implicitHeight: 40
            radius: Theme.radius
            color: continueHover.hovered ? Theme.accentHover : Theme.accent

            HoverHandler { id: continueHover }
            TapHandler { onSingleTapped: root.auth.finish_browser_login(redirect.text) }

            Text {
                anchors.centerIn: parent
                text: "Continue"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.weight: Font.DemiBold
                color: Theme.onAccent
            }
        }

        // ---- the device code ----------------------------------------
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            visible: root.auth.user_code.length > 0
            implicitWidth: codeText.implicitWidth + Theme.spaceXl
            implicitHeight: 64
            radius: Theme.radius
            color: Theme.elevated
            border.color: Theme.accent
            border.width: 1

            Text {
                id: codeText
                anchors.centerIn: parent
                text: root.auth.user_code
                font.family: Theme.monoFamily
                font.pixelSize: 30
                font.letterSpacing: 6
                color: Theme.accent
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.auth.verification_uri.length > 0
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
            text: root.auth.verification_uri
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textSecondary
        }

        // ---- sign-in button -----------------------------------------
        Rectangle {
            id: signIn
            Layout.alignment: Qt.AlignHCenter
            visible: !root.auth.awaiting_redirect && root.auth.user_code.length === 0
            implicitWidth: 220
            implicitHeight: 48
            radius: Theme.radius
            color: root.auth.busy ? Theme.button
                 : signInHover.hovered ? Theme.accentHover : Theme.accent
            opacity: root.auth.busy ? 0.6 : 1

            HoverHandler { id: signInHover; enabled: !root.auth.busy }
            TapHandler {
                enabled: !root.auth.busy
                onSingleTapped: root.auth.start_browser_login()
            }

            Text {
                anchors.centerIn: parent
                text: root.auth.busy ? "Working…" : "Sign in to TIDAL"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.weight: Font.DemiBold
                color: root.auth.busy ? Theme.textMuted : Theme.onAccent
            }
        }

        // Device code loses lossless, so it is offered quietly and labelled.
        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: !root.auth.awaiting_redirect && root.auth.user_code.length === 0
            text: "Use a login code instead (no lossless)"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            color: codeHover.hovered ? Theme.textSecondary : Theme.textFaint

            HoverHandler { id: codeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onSingleTapped: root.auth.start_login() }
        }

        // Waiting for the user to enter the code.
        Row {
            Layout.alignment: Qt.AlignHCenter
            visible: root.auth.busy && root.auth.user_code.length > 0
            spacing: 6

            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    width: 8
                    height: 8
                    radius: 4
                    color: Theme.accent

                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        PauseAnimation { duration: index * 160 }
                        NumberAnimation { to: 0.2; duration: 400 }
                        NumberAnimation { to: 1.0; duration: 400 }
                        PauseAnimation { duration: 480 - index * 160 }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.auth.error.length > 0
            implicitHeight: errText.implicitHeight + Theme.space
            radius: Theme.radiusSm
            color: Theme.elevated
            border.color: Theme.error
            border.width: 1

            Text {
                id: errText
                anchors.centerIn: parent
                width: parent.width - Theme.space
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: root.auth.error
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                color: Theme.textPrimary
            }
        }
    }
}
