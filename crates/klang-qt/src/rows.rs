//! One flattening of a track for every list in the UI.
//!
//! Each bridge grew its own copy of this while they were written in parallel;
//! they now share this one so a new column appears everywhere at once.

use klang_core::camelot;
use klang_core::tidal_api::TidalTrack;
use serde_json::{json, Value};

/// Artist id, from the same fallback chain as the name.
fn artist_id(track: &TidalTrack) -> Option<u64> {
    track
        .artist
        .as_ref()
        .map(|a| a.id)
        .or_else(|| track.artists.as_ref().and_then(|list| list.first().map(|a| a.id)))
}

/// Artist name, from `artist` or the first of `artists` — endpoints differ in
/// which of the two they populate.
fn artist_name(track: &TidalTrack) -> String {
    track
        .artist
        .as_ref()
        .map(|a| a.name.clone())
        .or_else(|| {
            track
                .artists
                .as_ref()
                .and_then(|list| list.first().map(|a| a.name.clone()))
        })
        .unwrap_or_default()
}

/// The tier a row's badge shows.
///
/// `audio_quality` still reports LOSSLESS for Hi-Res tracks on the v1
/// endpoints; tidal.com reads `mediaMetadata.tags` instead, which is where
/// HIRES_LOSSLESS actually appears.
fn quality_tier(track: &TidalTrack) -> String {
    let tags = track
        .media_metadata
        .as_ref()
        .map(|m| m.tags.as_slice())
        .unwrap_or_default();
    if tags.iter().any(|t| t == "HIRES_LOSSLESS") {
        return "HI_RES_LOSSLESS".to_string();
    }
    if tags.iter().any(|t| t == "LOSSLESS") {
        return "LOSSLESS".to_string();
    }
    track.audio_quality.clone().unwrap_or_default()
}

/// The id of a track's own radio mix, used by autoplay once the queue runs
/// out. TIDAL nests it under `mixes.TRACK_MIX`.
fn track_mix_id(track: &TidalTrack) -> Option<String> {
    track
        .mixes
        .as_ref()?
        .get("TRACK_MIX")?
        .as_str()
        .map(str::to_string)
}

/// The shape every track list binds to.
///
/// `bpm` and `key` come straight off TIDAL's v1 track payload — upstream never
/// modelled the fields, so serde was discarding them. `key` is rendered as a
/// Camelot code, matching what tidal.com shows in its own key column.
pub fn track(index: usize, t: &TidalTrack) -> Value {
    json!({
        "index": index,
        "id": t.id,
        "title": t.title,
        "artist": artist_name(t),
        "artistId": artist_id(t),
        "album": t.album.as_ref().map(|a| a.title.clone()).unwrap_or_default(),
        "albumId": t.album.as_ref().map(|a| a.id),
        "duration": t.duration,
        "quality": quality_tier(t),
        "bpm": t.bpm,
        "key": camelot::camelot(t.key.as_deref(), t.key_scale.as_deref()),
        "explicit": t.explicit.unwrap_or(false),
        "ai": t.ai.unwrap_or(false),
        "trackNumber": t.track_number,
        "volumeNumber": t.volume_number,
        "cover": t.album.as_ref().and_then(|a| a.cover.clone()),
        // Only collections fill this in; a catalogue listing has no
        // "added" to speak of.
        "dateAdded": t.date_added,
        "trackMix": track_mix_id(t),
    })
}

/// Same shape, for callers that do not care about the position.
pub fn track_unindexed(t: &TidalTrack) -> Value {
    track(0, t)
}
