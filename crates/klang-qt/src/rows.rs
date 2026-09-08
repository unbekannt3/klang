//! One flattening of a track for every list in the UI.
//!
//! Each bridge grew its own copy of this while they were written in parallel;
//! they now share this one so a new column appears everywhere at once.

use klang_core::camelot;
use klang_core::tidal_api::TidalTrack;
use serde_json::{json, Value};

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
        "album": t.album.as_ref().map(|a| a.title.clone()).unwrap_or_default(),
        "duration": t.duration,
        "quality": t.audio_quality.clone().unwrap_or_default(),
        "bpm": t.bpm,
        "key": camelot::camelot(t.key.as_deref(), t.key_scale.as_deref()),
        "explicit": t.explicit.unwrap_or(false),
        "ai": t.ai.unwrap_or(false),
        "trackNumber": t.track_number,
        "volumeNumber": t.volume_number,
        "cover": t.album.as_ref().and_then(|a| a.cover.clone()),
    })
}

/// Same shape, for callers that do not care about the position.
pub fn track_unindexed(t: &TidalTrack) -> Value {
    track(0, t)
}
