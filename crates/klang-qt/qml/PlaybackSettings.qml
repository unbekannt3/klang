// Streaming quality, output device and pipeline toggles.

import QtQuick
import QtQuick.Layouts
import me.unbk.klang

ColumnLayout {
    id: root

    required property var settings

    spacing: Theme.space

    readonly property var qualities: [
        { value: "HI_RES_LOSSLESS", label: "Max" },
        { value: "LOSSLESS", label: "High" },
        { value: "HIGH", label: "Normal" },
    ]
    readonly property var devices: JSON.parse(root.settings.audio_devices_json || "[]")

    // Shared by the quality tier and the output device picker: a small
    // pill that shows selected state via border + fill rather than a
    // native control, matching the rest of the app.
    component Pill: Rectangle {
        id: pill
        required property string label
        property bool active: false
        signal clicked()

        implicitWidth: pillText.implicitWidth + Theme.space
        implicitHeight: 32
        radius: Theme.radiusSm
        color: pill.active ? Theme.hlMed : hover.hovered ? Theme.hlFaint : "transparent"
        border.color: pill.active ? Theme.accent : Theme.border
        border.width: 1

        HoverHandler { id: hover }
        TapHandler { onSingleTapped: pill.clicked() }

        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            color: pill.active ? Theme.textPrimary : Theme.textSecondary
        }
    }

    SettingRow {
        Layout.fillWidth: true
        label: "Maximum streaming quality"
        description: "Caps what klang asks TIDAL for; a track still falls back to a lower tier if it isn't available at this one."

        Row {
            spacing: Theme.spaceSm
            Repeater {
                model: root.qualities
                Pill {
                    required property var modelData
                    label: modelData.label
                    active: root.settings.max_quality === modelData.value
                    onClicked: root.settings.apply_max_quality(modelData.value)
                }
            }
        }
    }

    SettingRow {
        Layout.fillWidth: true
        label: "Output device"
        description: root.settings.exclusive_mode
                    ? "Used while exclusive device mode is on."
                    : "Only takes effect once exclusive device mode is on."
        enabled: root.settings.exclusive_mode && root.devices.length > 0

        Row {
            spacing: Theme.spaceSm
            Repeater {
                model: root.devices
                Pill {
                    required property var modelData
                    label: modelData.name
                    active: root.settings.exclusive_device === modelData.id
                    onClicked: root.settings.apply_exclusive_device(modelData.id)
                }
            }
        }
    }

    SettingRow {
        Layout.fillWidth: true
        label: "Volume normalization"
        description: "Levels tracks to a consistent loudness using TIDAL's replay-gain data."
        toggleMode: true
        checked: root.settings.volume_normalization
        onToggled: (value) => root.settings.apply_volume_normalization(value)
    }

    SettingRow {
        Layout.fillWidth: true
        label: "Autoplay"
        description: "When the queue runs out, keep going with a radio built from the last track."
        toggleMode: true
        checked: root.settings.autoplay
        onToggled: (value) => root.settings.apply_autoplay(value)
    }

    SettingRow {
        Layout.fillWidth: true
        label: "Explicit content"
        description: "Allow explicit tracks in radio and autoplay. Tracks you pick yourself are never filtered."
        toggleMode: true
        checked: root.settings.allow_explicit
        onToggled: (value) => root.settings.apply_allow_explicit(value)
    }

    SettingRow {
        Layout.fillWidth: true
        label: "Gapless playback"
        description: root.settings.gapless_supported
                    ? "Removes silence between consecutive tracks."
                    : "Not supported by this build's audio pipeline."
        toggleMode: true
        enabled: root.settings.gapless_supported
        checked: root.settings.gapless
        onToggled: (value) => root.settings.apply_gapless(value)
    }

    SettingRow {
        Layout.fillWidth: true
        label: "Exclusive device mode"
        description: "Locks the output device for klang alone instead of sharing it through the system mixer."
        toggleMode: true
        checked: root.settings.exclusive_mode
        onToggled: (value) => root.settings.apply_exclusive_mode(value)
    }

    SettingRow {
        Layout.fillWidth: true
        label: "Bit-perfect output"
        description: "Disables resampling. Requires — and turns on — exclusive device mode."
        toggleMode: true
        checked: root.settings.bit_perfect
        onToggled: (value) => root.settings.apply_bit_perfect(value)
    }
}
