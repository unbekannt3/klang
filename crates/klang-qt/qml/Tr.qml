// Translations. The English text is the key, so call sites stay readable and
// an untranslated string simply shows through in English.
//
// This is a plain table rather than Qt Linguist: klang ships two languages,
// and the .ts/.qm toolchain would add a build step and a translator binding
// that cxx-qt does not expose.
pragma Singleton

import QtQuick

QtObject {
    id: root

    /// "auto", "en" or "de". Main binds this to the saved setting.
    property string language: "auto"

    readonly property string resolved: language === "auto"
        ? (Qt.locale().name.startsWith("de") ? "de" : "en")
        : language

    readonly property var german: ({
        // Navigation
        "Home": "Startseite",
        "Explore": "Entdecken",
        "Feed": "Feed",
        "Settings": "Einstellungen",
        "My collection": "Meine Musik",
        "Tracks": "Titel",
        "Albums": "Alben",
        "Artists": "Künstler",
        "Playlists": "Playlists",
        "Search": "Suchen",
        "Profile": "Profil",
        "Log out": "Abmelden",

        // Pages
        "Loved Tracks": "Lieblingstitel",
        "Popular tracks": "Beliebte Titel",
        "Public playlists": "Öffentliche Playlists",
        "View all": "Alle anzeigen",
        "About this album": "Über dieses Album",
        "Credits": "Mitwirkende",
        "Lyrics": "Songtext",
        "Play queue": "Warteschlange",
        "Suggested tracks": "Vorgeschlagene Titel",
        "Now playing": "Wird gespielt",
        "Next up": "Als Nächstes",
        "History": "Verlauf",

        // Table columns
        "TITLE": "TITEL",
        "ARTIST": "KÜNSTLER",
        "ALBUM": "ALBUM",
        "BPM": "BPM",
        "KEY": "TONART",
        "LENGTH": "LÄNGE",
        "Filter by title, artist or album": "Nach Titel, Künstler oder Album filtern",

        // Transport and actions
        "Play": "Abspielen",
        "Pause": "Pause",
        "Shuffle": "Zufall",
        "Edit": "Bearbeiten",
        "Save": "Speichern",
        "Cancel": "Abbrechen",
        "Close": "Schließen",
        "Delete": "Löschen",
        "Rename": "Umbenennen",
        "Show": "Anzeigen",
        "Hide": "Verbergen",
        "Regenerate": "Neu erzeugen",

        // Context menus
        "Play now": "Jetzt abspielen",
        "Play next": "Als Nächstes",
        "Add to queue": "Zur Warteschlange",
        "Add to playlist": "Zu Playlist hinzufügen",
        "Add to Loved Tracks": "Zu Lieblingstiteln",
        "Remove from Loved Tracks": "Aus Lieblingstiteln entfernen",
        "Add to library": "Zur Sammlung",
        "Remove from library": "Aus Sammlung entfernen",
        "Follow artist": "Künstler folgen",
        "Unfollow artist": "Künstler nicht mehr folgen",
        "Go to album": "Zum Album",
        "Go to artist": "Zum Künstler",
        "Track radio": "Titel-Radio",
        "Block track": "Titel blockieren",
        "Unblock track": "Titel entsperren",
        "Block artist": "Künstler blockieren",
        "Unblock artist": "Künstler entsperren",
        "Edit playlist": "Playlist bearbeiten",
        "Delete playlist": "Playlist löschen",
        "Move to folder": "In Ordner verschieben",
        "New folder": "Neuer Ordner",

        // Empty and error states
        "Nothing here": "Nichts vorhanden",
        "Nothing here yet": "Noch nichts vorhanden",
        "Nothing to explore yet": "Noch nichts zu entdecken",
        "No tracks": "Keine Titel",
        "No credits for this track": "Keine Mitwirkenden für diesen Titel",
        "No lyrics for this track": "Kein Songtext für diesen Titel",
        "No suggestions for this track": "Keine Vorschläge für diesen Titel",
        "This playlist has no tracks": "Diese Playlist enthält keine Titel",
        "This mix has no tracks": "Dieser Mix enthält keine Titel",

        // Settings
        "Themes": "Design",
        "General": "Allgemein",
        "Playback": "Wiedergabe",
        "Scrobbling": "Scrobbeln",
        "Discord": "Discord",
        "MCP": "MCP",
        "Overlay": "Overlay",
        "Network": "Netzwerk",
        "Utilities": "Werkzeuge",
        "Language": "Sprache",
        "Automatic": "Automatisch",
        "English": "Englisch",
        "German": "Deutsch",
        "Maximum streaming quality": "Maximale Streaming-Qualität",
        "Output device": "Ausgabegerät",
        "Volume normalization": "Lautstärke-Normalisierung",
        "Autoplay": "Automatisch weiterspielen",
        "Explicit content": "Anstößige Inhalte",
        "Gapless playback": "Lückenlose Wiedergabe",
        "Exclusive device mode": "Exklusiver Gerätemodus",
        "Bit-perfect output": "Bit-perfekte Ausgabe",
        "Keyboard shortcuts": "Tastaturkürzel",
        "Automatic follows the system locale.": "Automatisch folgt der Systemsprache.",
        "Close to tray": "In Systemleiste minimieren",
        "Minimize to the system tray instead of quitting when the window is closed.":
            "Beim Schließen in die Systemleiste minimieren statt zu beenden.",
    })

    /// Translate one English string. An entry that is missing falls through
    /// untranslated, which is what a half-finished translation should do.
    function t(text) {
        if (root.resolved !== "de")
            return text
        const translated = root.german[text]
        return translated !== undefined ? translated : text
    }
}
