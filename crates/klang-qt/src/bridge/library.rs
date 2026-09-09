//! The user's library: loved tracks, favourite albums/artists/playlists/
//! videos, and favourite mixes.
//!
//! The list crosses into QML as a JSON string that `JSON.parse` turns into a
//! plain JS array, which `ListView` accepts as a model. That is the walking
//! skeleton's shortcut — a real `QAbstractListModel` with roles and paging is
//! phase-2 work, and is what virtualised scrolling over thousands of rows
//! needs.

use crate::core as app;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use klang_core::api::library;
use klang_core::tidal_api::{TidalAlbumDetail, TidalArtistDetail, TidalFavoriteMix, TidalPlaylist, TidalVideo};
use serde_json::{json, Value};
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
        #[qproperty(QString, tracks_json)]
        #[qproperty(QString, error)]
        #[qproperty(i32, total)]
        /// Whether another page of loved tracks is waiting.
        #[qproperty(bool, has_more)]
        #[qproperty(QString, albums_json)]
        #[qproperty(QString, artists_json)]
        #[qproperty(QString, playlists_json)]
        #[qproperty(QString, videos_json)]
        #[qproperty(QString, mixes_json)]
        #[qproperty(QString, sort_order)]
        #[qproperty(QString, sort_direction)]
        type LibraryController = super::LibraryControllerRust;

        /// Load the first page of loved tracks for the signed-in user, sorted
        /// by `sort_order`/`sort_direction`.
        #[qinvokable]
        fn load_favorites(self: Pin<&mut LibraryController>, user_id: i64, limit: i32);

        /// Append the next page of loved tracks. No-op while one is in
        /// flight or once the last page has arrived.
        #[qinvokable]
        fn load_more_favorites(self: Pin<&mut LibraryController>);

        /// Load favourite albums as card rows (`albums_json`).
        #[qinvokable]
        fn load_albums(self: Pin<&mut LibraryController>, user_id: i64, limit: i32);

        /// Load favourite artists as card rows (`artists_json`).
        #[qinvokable]
        fn load_artists(self: Pin<&mut LibraryController>, user_id: i64, limit: i32);

        /// Load favourite playlists as card rows (`playlists_json`).
        #[qinvokable]
        fn load_playlists(self: Pin<&mut LibraryController>, user_id: i64, limit: i32);

        /// Load favourite videos as card rows (`videos_json`).
        #[qinvokable]
        fn load_videos(self: Pin<&mut LibraryController>, user_id: i64);

        /// Load favourite mixes as card rows (`mixes_json`). Mixes are not
        /// keyed by user id — see `load_mixes`.
        #[qinvokable]
        fn load_mixes(self: Pin<&mut LibraryController>, limit: i32);

        /// Change the loved-tracks sort and reload it with the user/limit
        /// from the last `load_favorites` call.
        #[qinvokable]
        fn set_sort(self: Pin<&mut LibraryController>, order: &QString, direction: &QString);
    }

    impl cxx_qt::Threading for LibraryController {}
}

pub struct LibraryControllerRust {
    loading: bool,
    tracks_json: QString,
    error: QString,
    total: i32,
    albums_json: QString,
    artists_json: QString,
    playlists_json: QString,
    videos_json: QString,
    mixes_json: QString,
    sort_order: QString,
    sort_direction: QString,
    /// Remembered so `set_sort` can redo the same load with a new order.
    fav_user_id: i64,
    fav_limit: i32,
    /// How many loved tracks are already in `tracks_json`.
    fav_loaded: i32,
    has_more: bool,
}

/// `DATE`/`DESC` is TIDAL's own default for every favourites endpoint, and
/// what upstream sone always sent — kept as the initial sort here too.
impl Default for LibraryControllerRust {
    fn default() -> Self {
        Self {
            loading: false,
            tracks_json: QString::default(),
            error: QString::default(),
            total: 0,
            albums_json: QString::default(),
            artists_json: QString::default(),
            playlists_json: QString::default(),
            videos_json: QString::default(),
            mixes_json: QString::default(),
            sort_order: QString::from("DATE"),
            sort_direction: QString::from("DESC"),
            fav_user_id: 0,
            fav_limit: 0,
            fav_loaded: 0,
            has_more: false,
        }
    }
}

/// Artist name for an album card, the same `artist`/`artists` fallback chain
/// `rows::track` uses for tracks — TIDAL populates whichever field the
/// endpoint favours.
fn album_artist_name(album: &TidalAlbumDetail) -> String {
    album
        .artist
        .as_ref()
        .map(|a| a.name.clone())
        .or_else(|| album.artists.as_ref().and_then(|list| list.first().map(|a| a.name.clone())))
        .unwrap_or_default()
}

/// Same fallback as `album_artist_name`, for `TidalVideo`'s identical
/// `artist`/`artists` pair.
fn video_artist_name(video: &TidalVideo) -> String {
    video
        .artist
        .as_ref()
        .map(|a| a.name.clone())
        .or_else(|| video.artists.as_ref().and_then(|list| list.first().map(|a| a.name.clone())))
        .unwrap_or_default()
}

/// Card row for an album: the same `{id, title, subtitle, image, kind}` shape
/// `CardCarousel`/`MediaCard` already consume (see `home.rs`), plus
/// `releaseDate` — album cards show the year.
fn album_card_row(album: &TidalAlbumDetail) -> Value {
    json!({
        "id": album.id,
        "title": album.title,
        "subtitle": album_artist_name(album),
        "image": album.cover.clone().unwrap_or_default(),
        "kind": "album",
        "releaseDate": album.release_date.clone().unwrap_or_default(),
    })
}

fn artist_card_row(artist: &TidalArtistDetail) -> Value {
    json!({
        "id": artist.id,
        "title": artist.name,
        "subtitle": "",
        "image": artist.picture.clone().unwrap_or_default(),
        "kind": "artist",
    })
}

/// Subtitle falls back to a track count, same as `home.rs`'s playlist rows.
fn playlist_card_row(playlist: &TidalPlaylist) -> Value {
    let subtitle = playlist
        .creator
        .as_ref()
        .and_then(|c| c.name.clone())
        .or_else(|| playlist.number_of_tracks.map(|n| format!("{n} tracks")))
        .unwrap_or_default();
    json!({
        "id": playlist.uuid,
        "title": playlist.title,
        "subtitle": subtitle,
        "image": playlist.image.clone().unwrap_or_default(),
        "kind": "playlist",
    })
}

/// TIDAL's favourites endpoint pages like the rest; `VIDEO_LIMIT` only stops
/// a library nobody could scroll through from paging forever.
const VIDEO_PAGE: u32 = 50;
const VIDEO_LIMIT: usize = 1000;

fn video_card_row(video: &TidalVideo) -> Value {
    json!({
        "id": video.id,
        "title": video.title,
        "subtitle": video_artist_name(video),
        "image": video.image_id.clone().unwrap_or_default(),
        "kind": "video",
    })
}

/// `TidalFavoriteMix.images` is `small`/`medium`/`large`, each already a full
/// URL — unlike other kinds' bare TIDAL image UUID (see `home.rs`'s mix
/// handling for the same distinction).
fn mix_card_row(mix: &TidalFavoriteMix) -> Value {
    let image = mix
        .images
        .as_ref()
        .and_then(|i| i.large.as_ref().or(i.medium.as_ref()).or(i.small.as_ref()))
        .map(|u| u.url.clone())
        .unwrap_or_default();
    json!({
        "id": mix.id,
        "title": mix.title.clone().unwrap_or_default(),
        "subtitle": mix.sub_title.clone().unwrap_or_default(),
        "image": image,
        "kind": "mix",
    })
}

impl qobject::LibraryController {
    pub fn load_favorites(mut self: Pin<&mut Self>, user_id: i64, limit: i32) {
        {
            let mut rust = self.as_mut().rust_mut();
            rust.fav_user_id = user_id;
            rust.fav_limit = limit;
            rust.fav_loaded = 0;
        }
        self.as_mut().set_tracks_json(QString::from("[]"));
        self.as_mut().set_has_more(false);
        self.fetch_favorites_page();
    }

    pub fn load_more_favorites(self: Pin<&mut Self>) {
        if !*self.has_more() || *self.loading() {
            return;
        }
        self.fetch_favorites_page();
    }

    /// Fetch one page and append it. The rows cross to QML as one JSON array,
    /// so appending means parsing what is already there — cheap next to the
    /// round-trip, and it keeps the single-property contract every list binds
    /// to.
    fn fetch_favorites_page(mut self: Pin<&mut Self>) {
        let user_id = self.rust().fav_user_id;
        if user_id == 0 {
            return;
        }
        let offset = self.rust().fav_loaded;
        let limit = self.rust().fav_limit.max(1);
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let order = self.rust().sort_order.to_string();
        let direction = self.rust().sort_direction.to_string();
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let result = library::get_favorite_tracks(
                app::state(),
                app::handle(),
                user_id as u64,
                offset.max(0) as u32,
                limit as u32,
                order,
                direction,
            )
            .await;

            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_loading(false);
                match result {
                    Ok(page) => {
                        let mut rows: Vec<serde_json::Value> =
                            serde_json::from_str(&obj.tracks_json().to_string())
                                .unwrap_or_default();
                        if offset == 0 {
                            rows.clear();
                        }
                        rows.extend(page.items.iter().map(crate::rows::track_unindexed));

                        let total = page.total_number_of_items as i32;
                        let loaded = rows.len() as i32;
                        obj.as_mut().rust_mut().fav_loaded = loaded;
                        obj.as_mut().set_total(total);
                        obj.as_mut().set_has_more(!page.items.is_empty() && loaded < total);

                        let json = serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into());
                        obj.as_mut().set_tracks_json(QString::from(&json));
                    }
                    Err(e) => obj.as_mut().set_error(QString::from(&e.to_string())),
                }
            });
        });
    }

    /// Named `set_sort`, not `set_sort_order` — cxx-qt already generates
    /// that name as the `sort_order` property's own setter.
    pub fn set_sort(mut self: Pin<&mut Self>, order: &QString, direction: &QString) {
        self.as_mut().set_sort_order(order.clone());
        self.as_mut().set_sort_direction(direction.clone());
        let user_id = self.rust().fav_user_id;
        let limit = self.rust().fav_limit;
        if user_id != 0 {
            self.load_favorites(user_id, limit);
        }
    }

    pub fn load_albums(mut self: Pin<&mut Self>, user_id: i64, limit: i32) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let result = library::get_favorite_albums(
                app::state(),
                app::handle(),
                user_id as u64,
                0,
                limit.max(1) as u32,
                "DATE".to_string(),
                "DESC".to_string(),
            )
            .await;

            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_loading(false);
                match result {
                    Ok(page) => {
                        let rows: Vec<_> = page.items.iter().map(album_card_row).collect();
                        let json = serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into());
                        obj.as_mut().set_albums_json(QString::from(&json));
                    }
                    Err(e) => {
                        obj.as_mut().set_albums_json(QString::from("[]"));
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }
            });
        });
    }

    pub fn load_artists(mut self: Pin<&mut Self>, user_id: i64, limit: i32) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let result = library::get_favorite_artists(
                app::state(),
                app::handle(),
                user_id as u64,
                0,
                limit.max(1) as u32,
                "DATE".to_string(),
                "DESC".to_string(),
            )
            .await;

            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_loading(false);
                match result {
                    Ok(page) => {
                        let rows: Vec<_> = page.items.iter().map(artist_card_row).collect();
                        let json = serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into());
                        obj.as_mut().set_artists_json(QString::from(&json));
                    }
                    Err(e) => {
                        obj.as_mut().set_artists_json(QString::from("[]"));
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }
            });
        });
    }

    /// `get_favorite_playlists` takes no `order`/`orderDirection` — unlike
    /// albums, artists, mixes and tracks, TIDAL's favourite-playlists
    /// endpoint doesn't accept them.
    pub fn load_playlists(mut self: Pin<&mut Self>, user_id: i64, limit: i32) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let result = library::get_favorite_playlists(
                app::state(),
                app::handle(),
                user_id as u64,
                0,
                limit.max(1) as u32,
            )
            .await;

            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_loading(false);
                match result {
                    Ok(page) => {
                        let rows: Vec<_> = page.items.iter().map(playlist_card_row).collect();
                        let json = serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into());
                        obj.as_mut().set_playlists_json(QString::from(&json));
                    }
                    Err(e) => {
                        obj.as_mut().set_playlists_json(QString::from("[]"));
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }
            });
        });
    }

    /// `get_favorite_videos` takes no `app_handle` and returns a plain
    /// `Vec` — unlike the others, it isn't disk-cached with a background
    /// refresh, and it reports no total, so a short page is what ends this.
    pub fn load_videos(mut self: Pin<&mut Self>, user_id: i64) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let mut videos = Vec::new();
            let mut offset = 0u32;
            let mut error = None;
            loop {
                match library::get_favorite_videos(app::state(), user_id as u64, offset, VIDEO_PAGE)
                    .await
                {
                    Ok(page) => {
                        let last = page.len() < VIDEO_PAGE as usize;
                        videos.extend(page);
                        if last || videos.len() >= VIDEO_LIMIT {
                            break;
                        }
                        offset += VIDEO_PAGE;
                    }
                    // Pages already fetched are still worth showing, so this
                    // reports the failure beside them rather than instead.
                    Err(e) => {
                        error = Some(e.to_string());
                        break;
                    }
                }
            }

            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_loading(false);
                let rows: Vec<_> = videos.iter().map(video_card_row).collect();
                let json = serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into());
                obj.as_mut().set_videos_json(QString::from(&json));
                if let Some(e) = error {
                    obj.as_mut().set_error(QString::from(&e));
                }
            });
        });
    }

    /// Mixes are global to the signed-in user's token, not keyed by an id —
    /// `get_favorite_mixes` takes no `user_id`.
    pub fn load_mixes(mut self: Pin<&mut Self>, limit: i32) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let result = library::get_favorite_mixes(
                app::state(),
                app::handle(),
                0,
                limit.max(1) as u32,
                "DATE".to_string(),
                "DESC".to_string(),
            )
            .await;

            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_loading(false);
                match result {
                    Ok(page) => {
                        let rows: Vec<_> = page.items.iter().map(mix_card_row).collect();
                        let json = serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into());
                        obj.as_mut().set_mixes_json(QString::from(&json));
                    }
                    Err(e) => {
                        obj.as_mut().set_mixes_json(QString::from("[]"));
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }
            });
        });
    }
}
