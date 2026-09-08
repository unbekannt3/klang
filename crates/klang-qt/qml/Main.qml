// klang — walking skeleton: sign in, list loved tracks, play one.
//
// Property and method names are snake_case because that is what cxx-qt 0.10
// puts on the Q_PROPERTY / Q_INVOKABLE, unchanged from the Rust side.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import me.unbk.klang

Kirigami.ApplicationWindow {
    id: root

    title: "klang"
    width: 1000
    height: 680
    minimumWidth: 480
    minimumHeight: 400

    AuthController {
        id: auth
        onLogged_inChanged: if (logged_in) library.load_favorites(auth.user_id, 100)
    }

    PlayerController {
        id: player
    }

    LibraryController {
        id: library
    }

    Component.onCompleted: {
        player.attach()
        auth.restore()
    }

    function fmt(secs) {
        if (!secs || secs < 0) return "0:00"
        const m = Math.floor(secs / 60)
        const s = Math.floor(secs % 60)
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    pageStack.initialPage: Kirigami.Page {
        id: page
        title: auth.logged_in ? "Loved Tracks" : "Sign in"
        padding: 0

        // ---- signed out ------------------------------------------------
        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - Kirigami.Units.gridUnit * 4,
                            Kirigami.Units.gridUnit * 26)
            spacing: Kirigami.Units.largeSpacing
            visible: !auth.logged_in

            Kirigami.Heading {
                Layout.fillWidth: true
                text: "klang"
                level: 1
                horizontalAlignment: Text.AlignHCenter
            }

            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: auth.user_code
                      ? "Open the page below and enter this code."
                      : "Sign in with your TIDAL account."
            }

            // The device code, once TIDAL has issued one.
            Kirigami.Heading {
                Layout.fillWidth: true
                visible: auth.user_code.length > 0
                level: 1
                horizontalAlignment: Text.AlignHCenter
                font.family: "monospace"
                font.letterSpacing: 4
                text: auth.user_code
            }

            QQC2.Label {
                Layout.fillWidth: true
                visible: auth.verification_uri.length > 0
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                text: auth.verification_uri
            }

            QQC2.Button {
                Layout.alignment: Qt.AlignHCenter
                visible: auth.user_code.length === 0
                enabled: !auth.busy
                icon.name: "user-identity"
                text: auth.busy ? "Working…" : "Sign in to TIDAL"
                onClicked: auth.start_login()
            }

            QQC2.BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                running: auth.busy && auth.user_code.length > 0
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: auth.error.length > 0
                type: Kirigami.MessageType.Error
                text: auth.error
            }
        }

        // ---- signed in: the track list ---------------------------------
        QQC2.ScrollView {
            anchors.fill: parent
            visible: auth.logged_in
            clip: true

            ListView {
                id: list
                model: JSON.parse(library.tracks_json || "[]")
                currentIndex: -1

                delegate: QQC2.ItemDelegate {
                    id: rowItem
                    required property var modelData
                    required property int index

                    width: list.width
                    highlighted: modelData.id === player.track_id

                    contentItem: RowLayout {
                        spacing: Kirigami.Units.largeSpacing

                        QQC2.Label {
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                            horizontalAlignment: Text.AlignRight
                            opacity: 0.5
                            text: rowItem.index + 1
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            QQC2.Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: rowItem.modelData.title
                                font.bold: rowItem.modelData.id === player.track_id
                            }

                            QQC2.Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                opacity: 0.6
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                text: rowItem.modelData.artist + " — " + rowItem.modelData.album
                            }
                        }

                        QQC2.Label {
                            opacity: 0.5
                            font.family: "monospace"
                            text: root.fmt(rowItem.modelData.duration)
                        }
                    }

                    onClicked: player.play(modelData.id, modelData.title,
                                           modelData.artist, modelData.duration)
                }

                Kirigami.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.gridUnit * 4
                    visible: list.count === 0 && !library.loading
                    icon.name: "emblem-favorite"
                    text: library.error.length > 0 ? library.error : "No loved tracks yet"
                }

                QQC2.BusyIndicator {
                    anchors.centerIn: parent
                    running: library.loading
                }
            }
        }
    }

    // ---- player bar ----------------------------------------------------
    footer: QQC2.ToolBar {
        visible: player.track_id !== 0
        // Two rows of text plus a slider need more than the single-line default.
        implicitHeight: Kirigami.Units.gridUnit * 3.5

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.largeSpacing
            anchors.rightMargin: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            QQC2.ToolButton {
                icon.name: player.playing ? "media-playback-pause" : "media-playback-start"
                enabled: !player.busy
                onClicked: player.toggle()
            }

            ColumnLayout {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                spacing: 0

                QQC2.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: player.title
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    opacity: 0.6
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: player.artist
                }
            }

            QQC2.Label {
                font.family: "monospace"
                opacity: 0.7
                text: root.fmt(player.position_secs)
            }

            QQC2.Slider {
                id: progress
                Layout.fillWidth: true
                from: 0
                to: Math.max(player.duration_secs, 1)
                // Follow the pipeline, except while the user is dragging.
                value: pressed ? value : player.position_secs
                onMoved: player.seek(value)
            }

            QQC2.Label {
                font.family: "monospace"
                opacity: 0.7
                text: root.fmt(player.duration_secs)
            }

            // What TIDAL actually served, not what was requested.
            QQC2.Label {
                visible: player.quality.length > 0
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.7
                text: player.quality
            }

            QQC2.Slider {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                from: 0
                to: 1
                value: 1
                onMoved: player.set_output_volume(value)
            }
        }
    }

    // Playback errors surface as a passive notification rather than stealing
    // focus mid-track.
    Connections {
        target: player
        function onErrorChanged() {
            if (player.error.length > 0)
                root.showPassiveNotification(player.error, "long")
        }
    }
}
