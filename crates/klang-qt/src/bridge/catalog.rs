//! Album and artist detail pages.
//!
//! Same shape as `library.rs`: each `#[qinvokable]` spawns onto
//! `klang_core::runtime`, awaits the plain-Rust API, and queues the result
//! back onto the Qt thread with `CxxQtThread::queue`. Album and artist detail
//! each need more than one call (header + tracks, header + bio + top tracks +
//! albums), so those are joined concurrently with `tokio::join!` rather than
//! awaited one after another.

use crate::core as app;
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use klang_core::api::pages;
use klang_core::tidal_api::{TidalAlbumDetail, TidalArtistDetail};
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
        #[qproperty(QString, album_json)]
        #[qproperty(QString, album_tracks_json)]
        #[qproperty(QString, artist_json)]
        #[qproperty(QString, artist_top_tracks_json)]
        #[qproperty(QString, artist_albums_json)]
        type CatalogController = super::CatalogControllerRust;

        /// Load an album's header (`album_json`) and its track list
        /// (`album_tracks_json`).
        #[qinvokable]
        fn load_album(self: Pin<&mut CatalogController>, album_id: i64);

        /// Load an artist's header (`artist_json`, bio included), their top
        /// tracks (`artist_top_tracks_json`) and their albums
        /// (`artist_albums_json`).
        #[qinvokable]
        fn load_artist(self: Pin<&mut CatalogController>, artist_id: i64);
    }

    impl cxx_qt::Threading for CatalogController {}
}

#[derive(Default)]
pub struct CatalogControllerRust {
    loading: bool,
    error: QString,
    album_json: QString,
    album_tracks_json: QString,
    artist_json: QString,
    artist_top_tracks_json: QString,
    artist_albums_json: QString,
}

/// An album's artist name and id. `TidalAlbumDetail.artist` is the singular
/// field the v1 API returns; the v2 API returns the plural `artists` array
/// instead, so fall back to its first entry — the same quirk `TidalTrack`
/// has, worked around there by `backfill_artist()`.
fn album_artist(album: &TidalAlbumDetail) -> (u64, String) {
    if let Some(a) = &album.artist {
        return (a.id, a.name.clone());
    }
    if let Some(list) = &album.artists {
        if let Some(a) = list.first() {
            return (a.id, a.name.clone());
        }
    }
    (0, String::new())
}

/// Flatten an album header: title, artist, cover, track count, total
/// duration, copyright, and — the reason this bridge exists — both dates
/// TIDAL exposes for a release.
///
/// `TidalAlbumDetail` carries two separate date fields: `release_date` and
/// `stream_start_date`. Upstream sone only ever surfaced `release_date`
/// (issue #186); both cross to QML here as `releaseDate` and
/// `originalReleaseDate` so the UI can show the distinction instead of
/// guessing which one a reissue's `release_date` actually refers to.
fn album_row(album: &TidalAlbumDetail) -> serde_json::Value {
    let (artist_id, artist) = album_artist(album);
    serde_json::json!({
        "id": album.id,
        "title": album.title,
        "artist": artist,
        "artistId": artist_id,
        "cover": album.cover.clone().unwrap_or_default(),
        "releaseDate": album.release_date.clone().unwrap_or_default(),
        "originalReleaseDate": album.stream_start_date.clone().unwrap_or_default(),
        "trackCount": album.number_of_tracks.unwrap_or(0),
        "duration": album.duration.unwrap_or(0),
        "copyright": album.copyright.clone().unwrap_or_default(),
        "albumType": album.album_type.clone().unwrap_or_default(),
        "explicit": album.explicit.unwrap_or(false),
    })
}

/// Flatten a track for the album/artist track lists. Same fields as
/// `library.rs`'s `row()` (`id`, `title`, `artist`, `album`, `duration`,
/// `quality`) plus disc/track numbers, which matter once tracks are shown in
/// album order rather than a flat favorites list.
/// Flatten an artist header. `TidalArtistDetail` has no bio or follower
/// count of its own — bio comes from the separate `get_artist_bio` call and
/// is passed in; TIDAL has no public follower-count endpoint for an
/// arbitrary artist (only for the signed-in user's own artist profile), so
/// it is left out — see the report for detail.
fn artist_row(artist: &TidalArtistDetail, bio: &str) -> serde_json::Value {
    serde_json::json!({
        "id": artist.id,
        "name": artist.name,
        "picture": artist.picture.clone().unwrap_or_default(),
        "bio": bio,
        "popularity": artist.popularity.unwrap_or(0),
    })
}

impl qobject::CatalogController {
    pub fn load_album(mut self: Pin<&mut Self>, album_id: i64) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let qt = self.qt_thread();
        let album_id = album_id.max(0) as u64;

        klang_core::runtime::spawn(async move {
            let (detail_result, tracks_result) = tokio::join!(
                pages::get_album_detail(app::state(), album_id),
                pages::get_album_tracks(app::state(), album_id, 0, 500),
            );

            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_loading(false);
                let mut errors = Vec::new();

                match detail_result {
                    Ok(detail) => {
                        let json = serde_json::to_string(&album_row(&detail))
                            .unwrap_or_else(|_| "{}".into());
                        obj.as_mut().set_album_json(QString::from(&json));
                    }
                    Err(e) => {
                        obj.as_mut().set_album_json(QString::from("{}"));
                        errors.push(e.to_string());
                    }
                }

                match tracks_result {
                    Ok(page) => {
                        let rows: Vec<_> = page.items.iter().map(crate::rows::track_unindexed).collect();
                        let json = serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into());
                        obj.as_mut().set_album_tracks_json(QString::from(&json));
                    }
                    Err(e) => {
                        obj.as_mut().set_album_tracks_json(QString::from("[]"));
                        errors.push(e.to_string());
                    }
                }

                if !errors.is_empty() {
                    obj.as_mut().set_error(QString::from(&errors.join("; ")));
                }
            });
        });
    }

    pub fn load_artist(mut self: Pin<&mut Self>, artist_id: i64) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let qt = self.qt_thread();
        let artist_id = artist_id.max(0) as u64;

        klang_core::runtime::spawn(async move {
            let (detail_result, bio_result, top_tracks_result, albums_result) = tokio::join!(
                pages::get_artist_detail(app::state(), artist_id),
                pages::get_artist_bio(app::state(), app::handle(), artist_id),
                pages::get_artist_top_tracks(app::state(), app::handle(), artist_id, 20),
                pages::get_artist_albums(app::state(), artist_id, 100),
            );
            // `get_artist_bio` treats a missing bio as success with an empty
            // string (not every artist has one), so it never contributes to
            // `errors` below.
            let bio = bio_result.unwrap_or_default();

            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_loading(false);
                let mut errors = Vec::new();

                match detail_result {
                    Ok(detail) => {
                        let json = serde_json::to_string(&artist_row(&detail, &bio))
                            .unwrap_or_else(|_| "{}".into());
                        obj.as_mut().set_artist_json(QString::from(&json));
                    }
                    Err(e) => {
                        obj.as_mut().set_artist_json(QString::from("{}"));
                        errors.push(e.to_string());
                    }
                }

                match top_tracks_result {
                    Ok(tracks) => {
                        let rows: Vec<_> = tracks.iter().map(crate::rows::track_unindexed).collect();
                        let json = serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into());
                        obj.as_mut().set_artist_top_tracks_json(QString::from(&json));
                    }
                    Err(e) => {
                        obj.as_mut().set_artist_top_tracks_json(QString::from("[]"));
                        errors.push(e.to_string());
                    }
                }

                match albums_result {
                    Ok(albums) => {
                        // Same `album_row` as `load_album` — each entry carries
                        // both `releaseDate` and `originalReleaseDate` too.
                        let rows: Vec<_> = albums.iter().map(album_row).collect();
                        let json = serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into());
                        obj.as_mut().set_artist_albums_json(QString::from(&json));
                    }
                    Err(e) => {
                        obj.as_mut().set_artist_albums_json(QString::from("[]"));
                        errors.push(e.to_string());
                    }
                }

                if !errors.is_empty() {
                    obj.as_mut().set_error(QString::from(&errors.join("; ")));
                }
            });
        });
    }
}
