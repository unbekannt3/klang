//! Camelot wheel notation, the way TIDAL labels a track's key.
//!
//! TIDAL's API gives `key` as a note name and `key_scale` as MAJOR or MINOR;
//! the web client shows the pair as a Camelot code ("4B", "11A"). DJs use it
//! because adjacent numbers are harmonically compatible.

/// Note names in the order the Camelot wheel walks them, with enharmonic
/// spellings TIDAL may use. Index is the semitone from C.
const SEMITONES: [(&str, &str); 12] = [
    ("C", "B#"),
    ("C#", "Db"),
    ("D", "D"),
    ("D#", "Eb"),
    ("E", "Fb"),
    ("F", "E#"),
    ("F#", "Gb"),
    ("G", "G"),
    ("G#", "Ab"),
    ("A", "A"),
    ("A#", "Bb"),
    ("B", "Cb"),
];

/// Camelot number for each semitone, major then minor.
/// C major is 8B, A minor is 8A; each fifth up moves one step clockwise.
const MAJOR_NUMBERS: [u8; 12] = [8, 3, 10, 5, 12, 7, 2, 9, 4, 11, 6, 1];
const MINOR_NUMBERS: [u8; 12] = [5, 12, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10];

fn semitone_of(note: &str) -> Option<usize> {
    let note = note.trim();
    SEMITONES
        .iter()
        .position(|(a, b)| a.eq_ignore_ascii_case(note) || b.eq_ignore_ascii_case(note))
}

/// `("A", "MINOR")` becomes `"11A"`. Returns `None` when either input is
/// missing or unrecognised, so callers can render a dash like TIDAL does.
pub fn camelot(key: Option<&str>, scale: Option<&str>) -> Option<String> {
    let semitone = semitone_of(key?)?;
    let minor = scale?.eq_ignore_ascii_case("MINOR");
    let number = if minor {
        MINOR_NUMBERS[semitone]
    } else {
        MAJOR_NUMBERS[semitone]
    };
    Some(format!("{number}{}", if minor { 'A' } else { 'B' }))
}

#[cfg(test)]
mod tests {
    use super::camelot;

    #[test]
    fn anchors_match_the_wheel() {
        // The two reference points every Camelot chart agrees on.
        assert_eq!(camelot(Some("C"), Some("MAJOR")).as_deref(), Some("8B"));
        assert_eq!(camelot(Some("A"), Some("MINOR")).as_deref(), Some("8A"));
    }

    #[test]
    fn walks_the_circle_of_fifths() {
        // Each fifth up is one step clockwise: C=8B, G=9B, D=10B, A=11B.
        assert_eq!(camelot(Some("G"), Some("MAJOR")).as_deref(), Some("9B"));
        assert_eq!(camelot(Some("D"), Some("MAJOR")).as_deref(), Some("10B"));
        assert_eq!(camelot(Some("A"), Some("MAJOR")).as_deref(), Some("11B"));
        assert_eq!(camelot(Some("E"), Some("MINOR")).as_deref(), Some("9A"));
    }

    #[test]
    fn accepts_enharmonic_spellings() {
        assert_eq!(
            camelot(Some("Db"), Some("MAJOR")),
            camelot(Some("C#"), Some("MAJOR"))
        );
        assert_eq!(camelot(Some("Ab"), Some("MAJOR")).as_deref(), Some("4B"));
    }

    #[test]
    fn missing_or_unknown_input_yields_nothing() {
        assert_eq!(camelot(None, Some("MAJOR")), None);
        assert_eq!(camelot(Some("A"), None), None);
        assert_eq!(camelot(Some("H"), Some("MAJOR")), None);
    }
}
