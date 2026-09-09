//! Catalogue search across tracks, albums, artists and playlists.
//!
//! Follows the shape of `library.rs`: properties for what QML binds to, a
//! `#[qinvokable]` entry point that spawns onto `klang_core::runtime` and
//! queues results back with `CxxQtThread::queue`. Each result category
//! crosses into QML as its own JSON string that `JSON.parse` turns into a
//! plain JS array — same walking-skeleton shortcut as the library list.

use crate::bridge::RequestSeq;
use crate::core as app;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use klang_core::api::search;
use std::pin::Pin;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(bool, loading)]
        #[qproperty(QString, error)]
        #[qproperty(QString, query)]
        #[qproperty(QString, tracks_json)]
        #[qproperty(QString, albums_json)]
        #[qproperty(QString, artists_json)]
        #[qproperty(QString, playlists_json)]
        #[qproperty(QString, videos_json)]
        type SearchController = super::SearchControllerRust;

        /// Search tracks, albums, artists and playlists for `query`.
        #[qinvokable]
        fn search(self: Pin<&mut SearchController>, query: &QString, limit: i32);

        /// Reset the query and every result list to empty.
        #[qinvokable]
        fn clear(self: Pin<&mut SearchController>);
    }

    impl cxx_qt::Threading for SearchController {}
}

#[derive(Default)]
pub struct SearchControllerRust {
    loading: bool,
    error: QString,
    query: QString,
    tracks_json: QString,
    albums_json: QString,
    artists_json: QString,
    playlists_json: QString,
    videos_json: QString,
    /// Typing is debounced, not cancelled, so several searches can be in
    /// flight at once; only the newest one may write its results.
    requests: RequestSeq,
}

/// Flatten a TIDAL track into what the list row needs. Artist comes from
/// `artist`, falling back to the first entry of `artists` — endpoints differ in
/// which of the two they populate.
/// Flatten a TIDAL album into what the list row needs. Artist falls back the
/// same way as tracks; `year` is the leading segment of `release_date`
/// ("2023-05-01" -> 2023), the same extraction the MCP sanitizer uses.
fn album_row(album: &klang_core::tidal_api::TidalAlbumDetail) -> serde_json::Value {
    let artist = album
        .artist
        .as_ref()
        .map(|a| a.name.clone())
        .or_else(|| {
            album
                .artists
                .as_ref()
                .and_then(|list| list.first().map(|a| a.name.clone()))
        })
        .unwrap_or_default();

    let year = album
        .release_date
        .as_ref()
        .and_then(|d| d.split('-').next().and_then(|y| y.parse::<u16>().ok()));

    serde_json::json!({
        "id": album.id,
        "title": album.title,
        "artist": artist,
        "year": year,
        "cover": album.cover.clone().unwrap_or_default(),
    })
}

/// Flatten a TIDAL artist into what the list row needs.
fn artist_row(artist: &klang_core::tidal_api::TidalArtist) -> serde_json::Value {
    serde_json::json!({
        "id": artist.id,
        "name": artist.name,
        "picture": artist.picture.clone().unwrap_or_default(),
    })
}

/// Flatten a TIDAL playlist into what the list row needs.
fn playlist_row(playlist: &klang_core::tidal_api::TidalPlaylist) -> serde_json::Value {
    serde_json::json!({
        "uuid": playlist.uuid,
        "title": playlist.title,
        "numberOfTracks": playlist.number_of_tracks.unwrap_or(0),
        "image": playlist.image.clone().unwrap_or_default(),
    })
}

/// Videos come back from the same search as everything else — TIDAL's own
/// query asks for VIDEOS — and render as cards, so this is the card shape
/// rather than a track row: a video is not playable through the audio queue.
fn video_row(video: &klang_core::tidal_api::TidalVideo) -> serde_json::Value {
    let artist = video
        .artist
        .as_ref()
        .map(|a| a.name.clone())
        .or_else(|| {
            video
                .artists
                .as_ref()
                .and_then(|list| list.first().map(|a| a.name.clone()))
        })
        .unwrap_or_default();
    serde_json::json!({
        "id": video.id,
        "title": video.title,
        "subtitle": artist,
        "image": video.image_id.clone().unwrap_or_default(),
        "kind": "video",
    })
}

impl qobject::SearchController {
    pub fn search(mut self: Pin<&mut Self>, query: &QString, limit: i32) {
        let query_string = String::from(query);
        let token = self.as_mut().rust_mut().requests.start();
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        self.as_mut().set_query(query.clone());
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let result =
                search::search_tidal(app::state(), query_string, limit.max(1) as u32).await;

            let _ = qt.queue(move |mut obj| {
                if !obj.rust().requests.is_current(token) {
                    return; // an answer for a query the user has since typed past
                }
                obj.as_mut().set_loading(false);
                match result {
                    Ok(results) => {
                        let tracks: Vec<_> = results.tracks.iter().map(crate::rows::track_unindexed).collect();
                        let albums: Vec<_> = results.albums.iter().map(album_row).collect();
                        let artists: Vec<_> = results.artists.iter().map(artist_row).collect();
                        let playlists: Vec<_> =
                            results.playlists.iter().map(playlist_row).collect();
                        let videos: Vec<_> = results.videos.iter().map(video_row).collect();

                        let tracks_json =
                            serde_json::to_string(&tracks).unwrap_or_else(|_| "[]".into());
                        let albums_json =
                            serde_json::to_string(&albums).unwrap_or_else(|_| "[]".into());
                        let artists_json =
                            serde_json::to_string(&artists).unwrap_or_else(|_| "[]".into());
                        let playlists_json =
                            serde_json::to_string(&playlists).unwrap_or_else(|_| "[]".into());
                        let videos_json =
                            serde_json::to_string(&videos).unwrap_or_else(|_| "[]".into());

                        obj.as_mut().set_tracks_json(QString::from(&tracks_json));
                        obj.as_mut().set_albums_json(QString::from(&albums_json));
                        obj.as_mut().set_artists_json(QString::from(&artists_json));
                        obj.as_mut().set_playlists_json(QString::from(&playlists_json));
                        obj.as_mut().set_videos_json(QString::from(&videos_json));
                    }
                    Err(e) => {
                        obj.as_mut().set_tracks_json(QString::from("[]"));
                        obj.as_mut().set_albums_json(QString::from("[]"));
                        obj.as_mut().set_artists_json(QString::from("[]"));
                        obj.as_mut().set_playlists_json(QString::from("[]"));
                        obj.as_mut().set_videos_json(QString::from("[]"));
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }
            });
        });
    }

    pub fn clear(mut self: Pin<&mut Self>) {
        // Whatever is still in flight was asked for a query that no longer
        // exists; its answer must not repopulate the cleared lists.
        self.as_mut().rust_mut().requests.cancel();
        self.as_mut().set_loading(false);
        self.as_mut().set_error(QString::from(""));
        self.as_mut().set_query(QString::from(""));
        self.as_mut().set_tracks_json(QString::from("[]"));
        self.as_mut().set_albums_json(QString::from("[]"));
        self.as_mut().set_artists_json(QString::from("[]"));
        self.as_mut().set_playlists_json(QString::from("[]"));
        self.as_mut().set_videos_json(QString::from("[]"));
    }
}
