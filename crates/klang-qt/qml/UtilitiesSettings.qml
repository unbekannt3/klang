// Disk cache stats/clear, and the file logging toggle + shortcut.
//
// cache_stats() is a plain invokable, not a property, so it is re-read
// explicitly after any action that can change it instead of via a binding.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

ColumnLayout {
    id: root

    required property var settings

    spacing: Theme.space

    property var cacheStats: ({})

    function refreshCacheStats() {
        try {
            root.cacheStats = JSON.parse(root.settings.cache_stats() || "{}")
        } catch (e) {
            root.cacheStats = {}
        }
    }

    Component.onCompleted: root.refreshCacheStats()

    readonly property string cacheSummary:
        Tr.t("%1 MB across %2 items — %3% of the %4 MB cap")
            .arg((root.cacheStats.totalDiskMb || 0).toFixed(1))
            .arg(root.cacheStats.totalEntries || 0)
            .arg(Math.round(root.cacheStats.usagePercent || 0))
            .arg((root.cacheStats.maxDiskMb || 0).toFixed(0))

    component ActionButton: Rectangle {
        id: btn
        required property string label
        signal clicked()

        implicitWidth: btnText.implicitWidth + Theme.space
        implicitHeight: 32
        radius: Theme.radiusSm
        color: hover.hovered ? Theme.hlFaint : "transparent"
        border.color: Theme.border
        border.width: 1

        HoverHandler { id: hover }
        TapHandler { onSingleTapped: btn.clicked() }

        Text {
            id: btnText
            anchors.centerIn: parent
            text: btn.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            color: Theme.textSecondary
        }
    }

    SettingRow {
        Layout.fillWidth: true
        label: Tr.t("Disk cache")
        description: root.cacheSummary

        ActionButton {
            label: Tr.t("Clear cache")
            onClicked: {
                root.settings.clear_cache()
                root.refreshCacheStats()
            }
        }
    }

    SettingRow {
        Layout.fillWidth: true
        label: Tr.t("Write logs to disk")
        description: Tr.t("Helps when reporting bugs. Capped at roughly 12 MB.")
        toggleMode: true
        checked: root.settings.enable_logging
        onToggled: (value) => root.settings.apply_enable_logging(value)
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.space
        visible: root.settings.enable_logging

        SettingRow {
            Layout.fillWidth: true
            label: Tr.t("Log folder")
            description: "~/.config/klang/logs"

            ActionButton {
                label: Tr.t("Open folder")
                onClicked: root.settings.open_log_folder()
            }
        }
    }
}
