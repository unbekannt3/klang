// Global keyboard shortcuts, ported from sone's src/lib/shortcuts.ts defaults.
// Klang has no rebinding UI, so these are fixed combos rather than sone's
// configurable/persisted bindings.
import QtQuick

Item {
    id: root

    required property var player      // PlayerController
    required property var favorites   // FavoritesController
    required property var settings    // SettingsController (bit-perfect / exclusive)

    signal searchRequested()
    signal helpRequested()
    signal dismissRequested()

    // Matches the step AppInitializer.tsx used for volumeUp/volumeDown.
    readonly property real volumeStep: 0.1

    Shortcut {
        sequence: "Space"
        onActivated: root.player.toggle()
    }

    Shortcut {
        sequence: "Ctrl+Right"
        autoRepeat: false
        onActivated: root.player.next()
    }

    Shortcut {
        sequence: "Ctrl+Left"
        autoRepeat: false
        onActivated: root.player.previous()
    }

    Shortcut {
        sequence: "Ctrl+Up"
        onActivated: root.player.set_output_volume(Math.min(1.0, root.player.volume + root.volumeStep))
    }

    Shortcut {
        sequence: "Ctrl+Down"
        onActivated: root.player.set_output_volume(Math.max(0.0, root.player.volume - root.volumeStep))
    }

    Shortcut {
        sequence: "M"
        autoRepeat: false
        onActivated: root.player.toggle_mute()
    }

    // Plain letters below only reach us once nothing editable has focus: a
    // focused TextInput claims them as typed characters via Qt's
    // ShortcutOverride before this Shortcut sees the key.
    Shortcut {
        sequence: "L"
        autoRepeat: false
        onActivated: {
            if (root.player.track_id !== 0)
                root.favorites.toggle_track(root.player.track_id)
        }
    }

    Shortcut {
        sequence: "Alt+S"
        autoRepeat: false
        onActivated: root.player.toggle_shuffle()
    }

    Shortcut {
        sequence: "Alt+R"
        autoRepeat: false
        onActivated: root.player.toggle_repeat()
    }

    Shortcut {
        sequence: "Ctrl+K"
        onActivated: root.searchRequested()
    }

    Shortcut {
        sequence: "Escape"
        onActivated: root.dismissRequested()
    }

    Shortcut {
        sequence: "Ctrl+E"
        autoRepeat: false
        onActivated: root.settings.apply_exclusive_mode(!root.settings.exclusive_mode)
    }

    Shortcut {
        sequence: "Ctrl+B"
        autoRepeat: false
        onActivated: root.settings.apply_bit_perfect(!root.settings.bit_perfect)
    }

    Shortcut {
        sequence: "Shift+/"
        onActivated: root.helpRequested()
    }
}
