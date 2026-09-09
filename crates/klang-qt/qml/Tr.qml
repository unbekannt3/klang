// Translations. The English text is the key, so call sites stay readable and
// an untranslated string simply shows through in English.
//
// This is a table rather than Qt Linguist: klang ships a couple of languages,
// and the .ts/.qm toolchain would add a build step and a QTranslator binding
// that cxx-qt does not expose.
//
// To add a language: write `TranslationsXx.qml` next to this file (copy
// TranslationsDe.qml), register it in build.rs, then add one entry to
// `catalogues` and one to `languages` below. Nothing else changes.
pragma Singleton

import QtQuick

QtObject {
    id: root

    /// Language code, or "auto" to follow the system locale. Main binds this
    /// to the saved setting.
    property string language: "auto"

    /// Every language the UI offers, in the order the picker shows them.
    /// "auto" is always first and has no catalogue of its own.
    readonly property var languages: [
        { code: "auto", label: "Automatic" },
        { code: "en",   label: "English" },
        { code: "de",   label: "German" },
    ]

    /// Code to string table. English needs no entry: it is the key set.
    readonly property var catalogues: ({
        "de": TranslationsDe.strings,
    })

    readonly property string resolved: {
        if (root.language !== "auto")
            return root.language
        // Qt reports e.g. "de_DE"; match on the language part alone.
        const system = Qt.locale().name.split("_")[0]
        return root.catalogues[system] !== undefined ? system : "en"
    }

    /// Translate one English string. A string the catalogue does not carry
    /// falls through untranslated, which is what a half-finished translation
    /// should look like.
    function t(text) {
        const catalogue = root.catalogues[root.resolved]
        if (catalogue === undefined)
            return text
        const translated = catalogue[text]
        return translated !== undefined ? translated : text
    }
}
