// The avatar button in the header: opens a small menu for the profile,
// settings and log-out — the rest of upstream's UserMenu (exclusive output,
// shortcuts, about) already lives in the settings/shortcuts pages this app
// has, so it is not duplicated here.

import QtQuick
import me.unbk.klang

Item {
    id: root

    property string avatarUrl: ""
    property string displayName: "Profile"

    signal profileRequested()
    signal settingsRequested()
    signal logoutRequested()

    implicitWidth: 28
    implicitHeight: 28

    HoverHandler { id: hover }
    TapHandler {
        onSingleTapped: menu.openAt(Qt.point(root.width, root.height + Theme.spaceXs), root)
    }

    CoverArt {
        anchors.fill: parent
        radius: width / 2
        uuid: root.avatarUrl
        placeholderGlyph: "☺"

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.color: hover.hovered ? Theme.textSecondary : "transparent"
            border.width: 1
        }
    }

    ContextMenu {
        id: menu
        model: [
            { label: root.displayName, icon: "artist", onTriggered: () => root.profileRequested() },
            { separator: true },
            { label: Tr.t("Settings"), icon: "settings", onTriggered: () => root.settingsRequested() },
            { separator: true },
            { label: Tr.t("Log out"), danger: true, onTriggered: () => root.logoutRequested() },
        ]
    }
}
