// Device-code sign-in. TIDAL issues a short code, the user types it into their
// own browser, and AuthController polls until the token lands. No web engine
// anywhere in the process.

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
            text: root.auth.user_code.length > 0
                  ? "Open the address below and enter this code."
                  : "Sign in with your TIDAL account."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textMuted
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
            visible: root.auth.user_code.length === 0
            implicitWidth: 220
            implicitHeight: 48
            radius: Theme.radius
            color: root.auth.busy ? Theme.button
                 : signInHover.hovered ? Theme.accentHover : Theme.accent
            opacity: root.auth.busy ? 0.6 : 1

            HoverHandler { id: signInHover; enabled: !root.auth.busy }
            TapHandler {
                enabled: !root.auth.busy
                onSingleTapped: root.auth.start_login()
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
