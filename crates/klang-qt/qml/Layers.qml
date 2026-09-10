// What covers what. Overlays name a tier instead of picking a number, so
// declaration order in Main.qml cannot decide what ends up on top.
//
// A new overlay picks the tier it belongs to; if none fits, add one here in
// order rather than inventing a z at the call site.

pragma Singleton

import QtQuick

QtObject {
    /// The pages, the sidebar, everything that scrolls.
    readonly property int page: 0
    /// Full-window views over a page: now playing.
    readonly property int panel: 100
    /// Transient hints anchored to something below: the artist card.
    readonly property int peek: 200
    /// The transport, which stays reachable over a panel.
    readonly property int player: 300
    /// Dialogs, which cover the transport too.
    readonly property int modal: 400
    /// A takeover that replaces the window's content: video.
    readonly property int takeover: 500
    /// Transient feedback, over everything.
    readonly property int notice: 600
}
