// An album/track's looping animated cover: TIDAL's own auto-playing preview
// clip, silent and looped, falling back to the static cover art when there is
// no animated cover or playback is turned off. Mirrors sone's
// TidalVideoCover.tsx, minus the poster-resolution plumbing CoverArt already
// does on its own (it sizes from the rendered item, not a requested bracket).

import QtQuick
import QtMultimedia
import me.unbk.klang

Item {
    id: root

    /// TIDAL cover UUID (poster / static fallback), or a full URL.
    property string cover: ""
    /// TIDAL animated-cover UUID, or a full URL; empty means no clip exists.
    property string videoCover: ""
    /// Off switches the clip and shows only the static cover — e.g. a
    /// data-saver preference upstream. `enabled` is already an Item property,
    /// hence the longer name.
    property bool animated: true
    /// Video resolution bracket: 640, 1280, or "origin" (native).
    property var size: 640

    function tidalVideoUrl(uuid, px) {
        if (!uuid)
            return ""
        if (uuid.startsWith("http"))
            return uuid
        const path = uuid.replace(/-/g, "/")
        const bracket = px === "origin" ? "origin" : (px <= 640 ? "640x640" : "1280x1280")
        return "https://resources.tidal.com/videos/" + path + "/" + bracket + ".mp4"
    }

    readonly property string resolvedVideoUrl: root.animated ? root.tidalVideoUrl(root.videoCover, root.size) : ""
    readonly property bool hasVideo: root.resolvedVideoUrl.length > 0

    CoverArt {
        anchors.fill: parent
        uuid: root.cover
        // Stays underneath as the poster until the clip has an actual frame,
        // and remains the fallback if the clip never loads.
        visible: !root.hasVideo || mediaPlayer.mediaStatus !== MediaPlayer.BufferedMedia
    }

    MediaPlayer {
        id: mediaPlayer
        source: root.hasVideo ? root.resolvedVideoUrl : ""
        loops: MediaPlayer.Infinite
        videoOutput: videoOutput
        // No `audioOutput` assigned: QtMultimedia stays silent without one,
        // which is exactly the "muted" playback these covers need.
        onSourceChanged: if (source.toString().length > 0) play()
    }

    VideoOutput {
        id: videoOutput
        anchors.fill: parent
        visible: root.hasVideo
        fillMode: VideoOutput.PreserveAspectCrop
    }
}
