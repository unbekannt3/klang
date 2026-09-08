//! Investigate why BPM/KEY show as dashes in Search results. Prints the raw JSON
//! TIDAL sends for a search's first track (before it goes through `TidalTrack`),
//! then checks the same thing for album tracks, artist top tracks and playlist
//! tracks, which each hit a different TIDAL endpoint.
//!
//!     cargo run -p klang-core --example search_bpm

use klang_core::tidal_api::TidalTrack;
use klang_core::{api, camelot, runtime, KlangCore};

fn fmt(t: &TidalTrack) -> String {
    let key = camelot::camelot(t.key.as_deref(), t.key_scale.as_deref())
        .unwrap_or_else(|| "-".into());
    let bpm = t.bpm.map(|b| b.to_string()).unwrap_or_else(|| "-".into());
    format!("{:<38.38} bpm={:>5} key={:>5}", t.title, bpm, key)
}

fn main() {
    let core = KlangCore::headless();
    runtime::block_on(async {
        if api::auth::load_saved_auth(core.state()).await.ok().flatten().is_none() {
            println!("not signed in — nothing to show");
            return;
        }

        let query = "Daft Punk";
        let mut client = core.state().tidal_client.lock().await;

        println!("=== SEARCH: raw JSON for tracks.items[0] (query={:?}) ===", query);
        let raw = client
            .search_v2_raw(query, 10)
            .await
            .expect("search_v2_raw failed");
        let json: serde_json::Value = serde_json::from_str(&raw).expect("search body is not JSON");
        let first_track_raw = json
            .get("tracks")
            .and_then(|t| t.get("items"))
            .and_then(|i| i.as_array())
            .and_then(|a| a.first());
        match first_track_raw {
            Some(t) => println!("{}", serde_json::to_string_pretty(t).unwrap()),
            None => println!("(no tracks in raw search response)"),
        }

        let results = client.search(query, 10).await.expect("search failed");
        println!("\n=== SEARCH: typed TidalTrack (via client.search) ===");
        for t in results.tracks.iter().take(5) {
            println!("{}", fmt(t));
        }

        if let Some(album) = results.tracks.first().and_then(|t| t.album.as_ref()) {
            let page = client
                .get_album_tracks(album.id, 0, 5)
                .await
                .expect("get_album_tracks failed");
            println!("\n=== ALBUM TRACKS: {:?} (id={}) ===", album.title, album.id);
            for t in &page.items {
                println!("{}", fmt(t));
            }
        }

        if let Some(artist) = results.tracks.first().and_then(|t| t.artist.as_ref()) {
            let top = client
                .get_artist_top_tracks(artist.id, 5)
                .await
                .expect("get_artist_top_tracks failed");
            println!("\n=== ARTIST TOP TRACKS: {:?} (id={}) ===", artist.name, artist.id);
            for t in &top {
                println!("{}", fmt(t));
            }
        }

        if let Some(pl) = results.playlists.first() {
            let tracks = client
                .get_playlist_tracks(&pl.uuid)
                .await
                .expect("get_playlist_tracks failed");
            println!("\n=== PLAYLIST TRACKS: {:?} (uuid={}) ===", pl.title, pl.uuid);
            for t in tracks.iter().take(5) {
                println!("{}", fmt(t));
            }
        }
    });
}
