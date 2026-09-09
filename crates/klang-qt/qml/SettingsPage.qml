import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import me.unbk.klang

Item {
    id: root

    property string section: "themes"

    readonly property var sections: [
        { key: "themes", label: Tr.t("Themes") },
        { key: "general", label: Tr.t("General") },
        { key: "playback", label: Tr.t("Playback") },
        { key: "scrobbling", label: Tr.t("Scrobbling") },
        { key: "discord", label: "Discord" },
        { key: "mcp", label: "MCP" },
        { key: "overlay", label: Tr.t("Overlay") },
        { key: "network", label: Tr.t("Network") },
        { key: "utilities", label: Tr.t("Utilities") },
    ]

    Rectangle { anchors.fill: parent; color: Theme.base }

    SettingsController { id: settingsCtl }
    Component.onCompleted: settingsCtl.load()

    component NavEntry: Rectangle {
        id: entry
        required property string sectionKey
        required property string sectionLabel
        readonly property bool active: root.section === entry.sectionKey

        Layout.fillWidth: true
        implicitHeight: 36
        radius: Theme.radiusSm
        color: entry.active ? Theme.hlMed : hover.hovered ? Theme.hlFaint : "transparent"

        HoverHandler { id: hover }
        TapHandler { onSingleTapped: root.section = entry.sectionKey }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spaceSm
            anchors.verticalCenter: parent.verticalCenter
            text: Tr.t(entry.sectionLabel)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.weight: entry.active ? Font.DemiBold : Font.Normal
            color: entry.active ? Theme.textPrimary : Theme.textSecondary
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        ColumnLayout {
            // Layouts default fillWidth/fillHeight to true for a nested
            // Layout child (unlike a plain Item), so this needs an explicit
            // false or it fights the Flickable below for width.
            Layout.fillWidth: false
            Layout.preferredWidth: 200
            Layout.fillHeight: true
            Layout.margins: Theme.spaceXl
            spacing: Theme.spaceXs

            Text {
                Layout.bottomMargin: Theme.space
                text: Tr.t("Settings")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeHeading
                font.weight: Font.Bold
                color: Theme.textPrimary
            }

            Repeater {
                model: root.sections
                NavEntry {
                    required property var modelData
                    Layout.fillWidth: true
                    sectionKey: modelData.key
                    sectionLabel: modelData.label
                }
            }

            Item { Layout.fillHeight: true }
        }

        Rectangle {
            Layout.fillHeight: true
            implicitWidth: 1
            color: Theme.border
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: pane.implicitHeight + Theme.spaceXl * 2
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            WheelScroller { view: flick; rowHeight: Theme.rowHeight }
            QQC2.ScrollBar.vertical: ThemedScrollBar { listHovered: paneHover.hovered }

            ColumnLayout {
                id: pane
                x: Theme.spaceXl
                y: Theme.spaceXl
                width: Math.min(flick.width - Theme.spaceXl * 2, 720)
                spacing: Theme.spaceLg

                Loader {
                    Layout.fillWidth: true
                    sourceComponent: switch (root.section) {
                        case "general":    return generalSection
                        case "playback":   return playbackSection
                        case "scrobbling": return scrobbleSection
                        case "discord":    return discordSection
                        case "mcp":        return mcpSection
                        case "overlay":    return overlaySection
                        case "network":    return networkSection
                        case "utilities":  return utilitiesSection
                        default:           return themesSection
                    }
                }
            }

            HoverHandler { id: paneHover }
        }
    }

    Component { id: themesSection; ThemePicker {} }
    Component { id: generalSection; GeneralSettings { settings: settingsCtl } }
    Component { id: playbackSection; PlaybackSettings { settings: settingsCtl } }
    Component { id: scrobbleSection; ScrobbleSettings { settings: settingsCtl } }
    Component { id: discordSection; DiscordSettings { settings: settingsCtl } }
    Component { id: mcpSection; McpSettings { settings: settingsCtl } }
    Component { id: overlaySection; OverlaySettings { settings: settingsCtl } }
    Component { id: networkSection; NetworkSettings { settings: settingsCtl } }
    Component { id: utilitiesSection; UtilitiesSettings { settings: settingsCtl } }

    // Ephemeral UI state, not a persisted setting, so clearing it with a
    // direct property write (rather than an apply_* invokable) is correct.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.space
        visible: settingsCtl.error.length > 0
        width: errorText.implicitWidth + Theme.spaceXl
        height: errorText.implicitHeight + Theme.space
        radius: Theme.radius
        color: Theme.elevated
        border.color: Theme.error
        border.width: 1

        Text {
            id: errorText
            anchors.centerIn: parent
            text: settingsCtl.error
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            color: Theme.textPrimary
        }

        Timer {
            running: settingsCtl.error.length > 0
            interval: 6000
            onTriggered: settingsCtl.error = ""
        }
    }
}
