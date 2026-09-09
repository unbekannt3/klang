// Full-screen music-video takeover. QtMultimedia (MediaPlayer + VideoOutput)
// owns playback; VideoController (video.rs) only resolves what to play and
// tracks the video's favourite state. This view has no dependency on the
// audio player or the track queue — starting a video only ever asks, via
// VideoController's `pause_audio_requested` signal, for the audio pipeline to
// be paused; see the report for how Main.qml should connect that.

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtMultimedia
import me.unbk.klang

Item {
    id: root

    required property var controller
    /// Needed for favourite-video writes; the controller has no auth state
    /// of its own (same convention as `FavoritesPage.userId`).
    property int userId: 0
    property real volume: 1

    /// The overlay dropped to the background; the video keeps playing.
    signal minimizeRequested()

    visible: controller.video_id !== 0
    // Sit above everything else, including the player bar.
    z: 1000

    readonly property var hostWindow: Window.window
    readonly property bool fullscreen: root.hostWindow !== null && root.hostWindow.visibility === Window.FullScreen
    readonly property var qualities: ["HIGH", "MEDIUM", "LOW"]

    property bool controlsVisible: true
    /// Position to restore once a quality switch's new source becomes
    /// seekable — swapping `source` resets QtMultimedia's own position.
    property real pendingResumeMs: -1

    function toggleFullscreen() {
        if (root.hostWindow)
            root.hostWindow.visibility = root.fullscreen ? Window.Windowed : Window.FullScreen
    }

    function resetHideTimer() {
        root.controlsVisible = true
        hideTimer.restart()
    }

    function selectQuality(q) {
        root.pendingResumeMs = mediaPlayer.position
        controller.select_quality(q)
    }

    /// Convenience entry point for callers that only know a video id — the
    /// signed-in user id is threaded through from `root.userId` rather than
    /// making every caller pass it.
    function open(videoId, quality) {
        controller.load_video(videoId, quality || "HIGH", root.userId)
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    ModalShield { blocksPage: true }

    MediaPlayer {
        id: mediaPlayer
        source: root.controller.stream_url
        audioOutput: AudioOutput { volume: root.volume }
        videoOutput: videoOutput

        onSourceChanged: if (source.toString().length > 0) play()

        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.LoadedMedia && root.pendingResumeMs >= 0) {
                const resumeMs = root.pendingResumeMs
                root.pendingResumeMs = -1
                mediaPlayer.setPosition(resumeMs)
                mediaPlayer.play()
            }
        }
    }

    VideoOutput {
        id: videoOutput
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
    }

    CoverArt {
        anchors.fill: parent
        uuid: root.controller.cover
        visible: !mediaPlayer.hasVideo
    }

    // Loading / error state, shown until the first frame is decoded.
    Item {
        anchors.fill: parent
        visible: controller.error.length > 0 || (!mediaPlayer.hasVideo && controller.loading)

        Text {
            anchors.centerIn: parent
            visible: controller.error.length > 0
            text: Tr.t("Unable to play this video")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textMuted
        }

        Rectangle {
            id: spinnerRing
            anchors.centerIn: parent
            visible: controller.error.length === 0
            width: 36
            height: 36
            radius: width / 2
            color: "transparent"
            border.width: 3
            border.color: Theme.hlMed

            Rectangle {
                width: 8
                height: 8
                radius: 4
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                color: Theme.accent
            }

            RotationAnimation on rotation {
                running: spinnerRing.visible
                from: 0
                to: 360
                duration: 900
                loops: Animation.Infinite
            }
        }
    }

    HoverHandler {
        id: moveHover
        cursorShape: root.controlsVisible ? Qt.ArrowCursor : Qt.BlankCursor
        onPointChanged: root.resetHideTimer()
    }

    TapHandler {
        onSingleTapped: mediaPlayer.playbackState === MediaPlayer.PlayingState ? mediaPlayer.pause() : mediaPlayer.play()
    }

    Timer {
        id: hideTimer
        interval: 3000
        onTriggered: root.controlsVisible = false
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.visible
        onActivated: root.fullscreen ? root.toggleFullscreen() : root.minimizeRequested()
    }

    component TransportButton: Rectangle {
        id: btn
        property string iconName: ""
        property int iconSize: 18
        property bool primary: false
        property bool on: false
        signal clicked()

        implicitWidth: primary ? 44 : 32
        implicitHeight: primary ? 44 : 32
        radius: Theme.radiusFull
        color: primary ? Theme.textPrimary : (hover.hovered ? Theme.hlMed : "transparent")

        HoverHandler { id: hover }
        TapHandler { onSingleTapped: btn.clicked() }

        Icon {
            anchors.centerIn: parent
            width: btn.iconSize
            height: btn.iconSize
            name: btn.iconName
            color: btn.primary ? Theme.base
                 : btn.on ? Theme.accent
                 : hover.hovered ? Theme.textPrimary : Theme.textSecondary
        }
    }

    // ---- top bar: title + minimize ---------------------------------
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 96
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.6) }
            GradientStop { position: 1.0; color: "transparent" }
        }
        opacity: root.controlsVisible ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.duration } }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.spaceLg
            spacing: Theme.space

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    spacing: Theme.spaceSm

                    Text {
                        Layout.fillWidth: true
                        text: root.controller.title
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLg
                        font.weight: Font.Bold
                        color: Theme.textPrimary
                    }

                    Rectangle {
                        visible: root.controller.explicit
                        implicitWidth: 18
                        implicitHeight: 18
                        radius: Theme.radiusXs
                        color: Theme.hlMed

                        Text {
                            anchors.centerIn: parent
                            text: "E"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm - 2
                            font.weight: Font.Bold
                            color: Theme.textSecondary
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.controller.artist.length > 0
                    text: root.controller.artist
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textMuted
                }
            }

            TransportButton {
                iconName: "close"
                iconSize: 16
                onClicked: root.minimizeRequested()
            }
        }
    }

    // ---- bottom bar: scrubber + transport ---------------------------
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 132
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.7) }
        }
        opacity: root.controlsVisible ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.duration } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spaceLg
            spacing: Theme.space

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spaceSm

                Text {
                    text: Format.duration(mediaPlayer.position / 1000)
                    font.family: Theme.fontFamilyMono
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textFaint
                }

                ProgressSlider {
                    id: scrubber
                    Layout.fillWidth: true
                    from: 0
                    to: mediaPlayer.duration / 1000
                    value: mediaPlayer.position / 1000
                    onSeeked: (v) => mediaPlayer.setPosition(v * 1000)
                }

                Text {
                    text: Format.duration(mediaPlayer.duration / 1000)
                    font.family: Theme.fontFamilyMono
                    font.pixelSize: Theme.fontSizeSm
                    color: Theme.textFaint
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space

                RowLayout {
                    Layout.preferredWidth: 140
                    spacing: Theme.spaceSm

                    TransportButton {
                        iconName: root.controller.is_favorite ? "heart-filled" : "heart"
                        on: root.controller.is_favorite
                        onClicked: root.controller.toggle_favorite()
                    }
                }

                Item { Layout.fillWidth: true }

                TransportButton {
                    primary: true
                    iconSize: 20
                    iconName: mediaPlayer.playbackState === MediaPlayer.PlayingState ? "pause" : "play"
                    onClicked: mediaPlayer.playbackState === MediaPlayer.PlayingState ? mediaPlayer.pause() : mediaPlayer.play()
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    Layout.preferredWidth: 140
                    Layout.alignment: Qt.AlignRight
                    spacing: Theme.space

                    ProgressSlider {
                        Layout.preferredWidth: 70
                        to: 1
                        value: root.volume
                        onSeeked: (v) => root.volume = v
                    }

                    TransportButton {
                        id: qualityButton
                        iconName: "settings"
                        iconSize: 16
                        onClicked: qualityMenu.openAt(Qt.point(width / 2, 0), qualityButton)
                    }

                    TransportButton {
                        iconName: root.fullscreen ? "restore" : "maximize"
                        iconSize: 16
                        onClicked: root.toggleFullscreen()
                    }
                }
            }
        }
    }

    ContextMenu {
        id: qualityMenu
        model: root.qualities.map((q) => ({
            label: Format.qualityName(q),
            onTriggered: () => root.selectQuality(q),
        }))
    }
}
