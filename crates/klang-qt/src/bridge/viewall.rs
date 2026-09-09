//! "View all" sub-pages: a home/library section, an artist's view-all list,
//! an Explore category, or an artist's full track list, each opened as its
//! own page instead of scrolling a strip.
//!
//! One controller backs all four because they share the same two shapes:
//! a flat grid of `{id, title, subtitle, image, kind}` rows (sections,
//! artist view-all, library favourites) or a flat list of tracks (an
//! artist's full track list). Item flattening is shared with `home.rs`
//! through `bridge/media_row.rs`.

use crate::bridge::media_row::{item_row, sections_to_json};
use crate::bridge::RequestSeq;
use crate::core as app;
use crate::rows;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use klang_core::api::{library, pages};
use klang_core::tidal_api::{
    HomePageSection, TidalAlbumDetail, TidalArtistDetail, TidalFavoriteMix, TidalPlaylist,
    TidalTrack,
};
use klang_core::SoneError;
use serde_json::{json, Value};
use std::pin::Pin;

/// TIDAL's view-all/track-all endpoints report no total, so a page shorter
/// than the request is the only "no more" signal available — the same
/// heuristic sone's own frontend uses.
const VIEW_ALL_PAGE_SIZE: u32 = 50;
const TRACKS_PAGE_SIZE: u32 = 50;
const LIBRARY_PAGE_SIZE: u32 = 50;

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
        /// Grid rows (`{id, title, subtitle, image, kind}`) for a section
        /// view-all, an artist view-all, or a library favourites list.
        #[qproperty(QString, items_json)]
        /// Whether `load_more_view_all`/`load_more_tracks`/`load_more_library`
        /// would fetch anything.
        #[qproperty(bool, has_more)]
        /// Known total item count (library favourites only); 0 when unknown.
        #[qproperty(i32, total)]
        /// `{title, kind, items}` carousels for an Explore category page —
        /// the same shape `SectionList` already renders.
        #[qproperty(QString, sections_json)]
        /// `{title, apiPath}` rows for an Explore link page (genres, moods,
        /// decades) — text buttons, not media cards.
        #[qproperty(QString, nav_items_json)]
        /// True when `load_explore_section` found only link rows, so the page
        /// should render `nav_items_json` instead of `sections_json`.
        #[qproperty(bool, is_nav_section)]
        /// Indexed track rows for an artist's full track list.
        #[qproperty(QString, tracks_json)]
        type ViewAllController = super::ViewAllControllerRust;

        /// Flatten every item in every section at `api_path` into one grid
        /// (`items_json`). Never paginates — matches `ViewAllPage.tsx`'s
        /// plain-apiPath branch, which loads its section once.
        #[qinvokable]
        fn load_section(self: Pin<&mut ViewAllController>, api_path: &QString);

        /// Load an Explore category. TIDAL shapes these two ways: a pure
        /// link cloud (genres/moods/decades — `nav_items_json`,
        /// `is_nav_section` true) or a page of media carousels
        /// (`sections_json`).
        #[qinvokable]
        fn load_explore_section(self: Pin<&mut ViewAllController>, api_path: &QString);

        /// First page of an artist sub-page's "view all" (albums, singles,
        /// similar artists, ...). `view_all_path` is the `apiPath` TIDAL
        /// attached to that section.
        #[qinvokable]
        fn load_artist_view_all(
            self: Pin<&mut ViewAllController>,
            artist_id: i64,
            view_all_path: &QString,
        );

        /// Next page of the load `load_artist_view_all` started, appended
        /// onto `items_json`. A no-op while already loading or `has_more` is
        /// false.
        #[qinvokable]
        fn load_more_view_all(self: Pin<&mut ViewAllController>);

        /// First page of an artist's full track list (`tracks_json`).
        #[qinvokable]
        fn load_artist_tracks(self: Pin<&mut ViewAllController>, artist_id: i64);

        /// Next page of the load `load_artist_tracks` started.
        #[qinvokable]
        fn load_more_tracks(self: Pin<&mut ViewAllController>);

        /// First page of a library favourites section. `kind` is one of
        /// "albums", "artists", "mixes" or "playlists".
        #[qinvokable]
        fn load_library(self: Pin<&mut ViewAllController>, kind: &QString, user_id: i64);

        /// Next page of the load `load_library` started.
        #[qinvokable]
        fn load_more_library(self: Pin<&mut ViewAllController>);

        /// Change sort order/direction and reload `load_library`'s section
        /// from the top. Playlists ignore this — see `fetch_library_page`.
        #[qinvokable]
        fn set_library_sort(
            self: Pin<&mut ViewAllController>,
            order: &QString,
            direction: &QString,
        );
    }

    impl cxx_qt::Threading for ViewAllController {}
}

pub struct ViewAllControllerRust {
    loading: bool,
    error: QString,
    items_json: QString,
    has_more: bool,
    total: i32,
    sections_json: QString,
    nav_items_json: QString,
    is_nav_section: bool,
    tracks_json: QString,

    // Paging state, remembered so `load_more_*` can continue a fetch without
    // the caller having to resend it. Not exposed to QML.
    view_all_artist_id: u64,
    view_all_path: String,
    view_all_offset: u32,
    view_all_items: Vec<Value>,

    tracks_artist_id: u64,
    tracks_offset: u32,
    tracks_rows: Vec<Value>,

    library_kind: String,
    library_user_id: u64,
    library_offset: u32,
    library_order: String,
    library_direction: String,
    library_items: Vec<Value>,

    // One sequence per independent load. `set_library_sort` in particular
    // restarts the library list while a page fetch is still in flight, and
    // that older page must not be appended onto the cleared vector.
    section_requests: RequestSeq,
    view_all_requests: RequestSeq,
    tracks_requests: RequestSeq,
    library_requests: RequestSeq,
}

/// `DATE`/`DESC` matches TIDAL's own default for every favourites endpoint —
/// same initial sort `bridge/library.rs` uses.
impl Default for ViewAllControllerRust {
    fn default() -> Self {
        Self {
            loading: false,
            error: QString::default(),
            items_json: QString::default(),
            has_more: false,
            total: 0,
            sections_json: QString::default(),
            nav_items_json: QString::default(),
            is_nav_section: false,
            tracks_json: QString::default(),
            view_all_artist_id: 0,
            view_all_path: String::new(),
            view_all_offset: 0,
            view_all_items: Vec::new(),
            tracks_artist_id: 0,
            tracks_offset: 0,
            tracks_rows: Vec::new(),
            library_kind: String::new(),
            library_user_id: 0,
            library_offset: 0,
            library_order: "DATE".to_string(),
            library_direction: "DESC".to_string(),
            library_items: Vec::new(),
            section_requests: RequestSeq::default(),
            view_all_requests: RequestSeq::default(),
            tracks_requests: RequestSeq::default(),
            library_requests: RequestSeq::default(),
        }
    }
}

/// `get_artist_view_all`/`get_artist_top_tracks_all` wrap each row as
/// `{data: {...}, ...}` in some responses and return the bare entity in
/// others — the same inconsistency sone's own frontend unwraps by hand.
fn unwrap_item(item: &Value) -> Value {
    item.get("data").cloned().unwrap_or_else(|| item.clone())
}

/// A section is a link cloud, not media, when it's declared as one or its
/// first item is a bare `{title, apiPath}` pointer (no `id`/`uuid`) — the
/// same detection `ExploreSubPage.tsx` uses for "All Genres"-style pages.
fn is_nav_link_section(section: &HomePageSection) -> bool {
    if section.section_type == "PAGE_LINKS_CLOUD" || section.section_type == "PAGE_LINKS" {
        return true;
    }
    section
        .items
        .as_array()
        .and_then(|items| items.first())
        .map(|first| {
            first.get("apiPath").is_some() && first.get("uuid").is_none() && first.get("id").is_none()
        })
        .unwrap_or(false)
}

fn nav_link_row(item: &Value) -> Value {
    let title = item
        .get("title")
        .and_then(|v| v.as_str())
        .or_else(|| item.get("name").and_then(|v| v.as_str()))
        .unwrap_or_default();
    let api_path = item.get("apiPath").and_then(|v| v.as_str()).unwrap_or_default();
    json!({ "title": title, "apiPath": api_path })
}

// ==================== Library favourites ====================
//
// Duplicates `bridge/library.rs`'s row shape rather than importing it — its
// helpers are private and that file is off-limits here.

fn library_album_artist(album: &TidalAlbumDetail) -> String {
    album
        .artist
        .as_ref()
        .map(|a| a.name.clone())
        .or_else(|| album.artists.as_ref().and_then(|list| list.first().map(|a| a.name.clone())))
        .unwrap_or_default()
}

fn library_album_row(album: &TidalAlbumDetail) -> Value {
    json!({
        "id": album.id,
        "title": album.title,
        "subtitle": library_album_artist(album),
        "image": album.cover.clone().unwrap_or_default(),
        "kind": "album",
    })
}

fn library_artist_row(artist: &TidalArtistDetail) -> Value {
    json!({
        "id": artist.id,
        "title": artist.name,
        "subtitle": "",
        "image": artist.picture.clone().unwrap_or_default(),
        "kind": "artist",
    })
}

fn library_playlist_row(playlist: &TidalPlaylist) -> Value {
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

fn library_mix_row(mix: &TidalFavoriteMix) -> Value {
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

/// Dispatches one library page fetch by kind and flattens it to grid rows.
/// Playlists are the odd one out: TIDAL's favourite-playlists endpoint takes
/// no `order`/`orderDirection`, unlike albums, artists and mixes (see
/// `bridge/library.rs`), so a sort change is silently a no-op there.
async fn fetch_library_kind(
    kind: &str,
    user_id: u64,
    offset: u32,
    limit: u32,
    order: String,
    direction: String,
) -> Result<(Vec<Value>, u32), SoneError> {
    match kind {
        "albums" => {
            let page =
                library::get_favorite_albums(app::state(), app::handle(), user_id, offset, limit, order, direction)
                    .await?;
            let rows = page.items.iter().map(library_album_row).collect();
            Ok((rows, page.total_number_of_items))
        }
        "artists" => {
            let page = library::get_favorite_artists(
                app::state(),
                app::handle(),
                user_id,
                offset,
                limit,
                order,
                direction,
            )
            .await?;
            let rows = page.items.iter().map(library_artist_row).collect();
            Ok((rows, page.total_number_of_items))
        }
        "mixes" => {
            let page =
                library::get_favorite_mixes(app::state(), app::handle(), offset, limit, order, direction).await?;
            let rows = page.items.iter().map(library_mix_row).collect();
            Ok((rows, page.total_number_of_items))
        }
        _ => {
            // Everything under "Playlists", not only the ones favourited from
            // someone else — get_favorite_playlists omits the user's own.
            let page = library::get_all_playlists(
                app::state(),
                app::handle(),
                user_id,
                offset,
                limit,
                order,
                direction,
            )
            .await?;
            let rows = page.items.iter().map(library_playlist_row).collect();
            Ok((rows, page.total_number_of_items))
        }
    }
}

impl qobject::ViewAllController {
    pub fn load_section(mut self: Pin<&mut Self>, api_path: &QString) {
        let token = self.as_mut().rust_mut().section_requests.start();
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        self.as_mut().set_has_more(false);
        let qt = self.qt_thread();
        let path = api_path.to_string();

        klang_core::runtime::spawn(async move {
            let result = pages::get_page_section(app::state(), app::handle(), path).await;

            let _ = qt.queue(move |mut obj| {
                if !obj.rust().section_requests.is_current(token) {
                    return;
                }
                obj.as_mut().set_loading(false);
                match result {
                    Ok(page) => {
                        let rows: Vec<Value> = page
                            .sections
                            .iter()
                            .flat_map(|s| {
                                s.items
                                    .as_array()
                                    .cloned()
                                    .unwrap_or_default()
                                    .into_iter()
                                    .map(move |it| item_row(&it, &s.section_type))
                            })
                            .collect();
                        let json = serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into());
                        obj.as_mut().set_items_json(QString::from(&json));
                    }
                    Err(e) => {
                        obj.as_mut().set_items_json(QString::from("[]"));
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }
            });
        });
    }

    pub fn load_explore_section(mut self: Pin<&mut Self>, api_path: &QString) {
        let token = self.as_mut().rust_mut().section_requests.start();
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let qt = self.qt_thread();
        let path = api_path.to_string();

        klang_core::runtime::spawn(async move {
            let result = pages::get_page_section(app::state(), app::handle(), path).await;

            let _ = qt.queue(move |mut obj| {
                if !obj.rust().section_requests.is_current(token) {
                    return;
                }
                obj.as_mut().set_loading(false);
                match result {
                    Ok(page) => {
                        let all_nav =
                            !page.sections.is_empty() && page.sections.iter().all(is_nav_link_section);
                        if all_nav {
                            let nav_rows: Vec<Value> = page
                                .sections
                                .iter()
                                .flat_map(|s| s.items.as_array().cloned().unwrap_or_default())
                                .map(|it| nav_link_row(&it))
                                .collect();
                            obj.as_mut().set_is_nav_section(true);
                            obj.as_mut().set_nav_items_json(QString::from(
                                &serde_json::to_string(&nav_rows).unwrap_or_else(|_| "[]".into()),
                            ));
                            obj.as_mut().set_sections_json(QString::from("[]"));
                        } else {
                            obj.as_mut().set_is_nav_section(false);
                            obj.as_mut().set_nav_items_json(QString::from("[]"));
                            obj.as_mut()
                                .set_sections_json(QString::from(&sections_to_json(&page.sections)));
                        }
                    }
                    Err(e) => {
                        obj.as_mut().set_is_nav_section(false);
                        obj.as_mut().set_sections_json(QString::from("[]"));
                        obj.as_mut().set_nav_items_json(QString::from("[]"));
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }
            });
        });
    }

    pub fn load_artist_view_all(mut self: Pin<&mut Self>, artist_id: i64, view_all_path: &QString) {
        {
            let mut rust = self.as_mut().rust_mut();
            rust.view_all_artist_id = artist_id.max(0) as u64;
            rust.view_all_path = view_all_path.to_string();
            rust.view_all_offset = 0;
            rust.view_all_items.clear();
        }
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        self.as_mut().set_has_more(false);
        self.fetch_view_all_page();
    }

    pub fn load_more_view_all(mut self: Pin<&mut Self>) {
        if !*self.has_more() || *self.loading() {
            return;
        }
        self.as_mut().set_loading(true);
        self.fetch_view_all_page();
    }

    fn fetch_view_all_page(mut self: Pin<&mut Self>) {
        let token = self.as_mut().rust_mut().view_all_requests.start();
        let artist_id = self.rust().view_all_artist_id;
        let path = self.rust().view_all_path.clone();
        let offset = self.rust().view_all_offset;
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let result = pages::get_artist_view_all(
                app::state(),
                app::handle(),
                artist_id,
                path,
                offset,
                VIEW_ALL_PAGE_SIZE,
            )
            .await;

            let _ = qt.queue(move |mut obj| {
                if !obj.rust().view_all_requests.is_current(token) {
                    return;
                }
                obj.as_mut().set_loading(false);
                match result {
                    Ok(value) => {
                        let items = value.get("items").and_then(|v| v.as_array()).cloned().unwrap_or_default();
                        let page_len = items.len() as u32;
                        let flattened: Vec<Value> =
                            items.iter().map(|it| item_row(&unwrap_item(it), "")).collect();
                        {
                            let mut rust = obj.as_mut().rust_mut();
                            rust.view_all_items.extend(flattened);
                            rust.view_all_offset += page_len;
                        }
                        let json = serde_json::to_string(&obj.rust().view_all_items).unwrap_or_else(|_| "[]".into());
                        obj.as_mut().set_items_json(QString::from(&json));
                        obj.as_mut().set_has_more(page_len >= VIEW_ALL_PAGE_SIZE);
                    }
                    Err(e) => {
                        obj.as_mut().set_has_more(false);
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }
            });
        });
    }

    pub fn load_artist_tracks(mut self: Pin<&mut Self>, artist_id: i64) {
        {
            let mut rust = self.as_mut().rust_mut();
            rust.tracks_artist_id = artist_id.max(0) as u64;
            rust.tracks_offset = 0;
            rust.tracks_rows.clear();
        }
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        self.as_mut().set_has_more(false);
        self.fetch_tracks_page();
    }

    pub fn load_more_tracks(mut self: Pin<&mut Self>) {
        if !*self.has_more() || *self.loading() {
            return;
        }
        self.as_mut().set_loading(true);
        self.fetch_tracks_page();
    }

    fn fetch_tracks_page(mut self: Pin<&mut Self>) {
        let token = self.as_mut().rust_mut().tracks_requests.start();
        let artist_id = self.rust().tracks_artist_id;
        let offset = self.rust().tracks_offset;
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let result =
                pages::get_artist_top_tracks_all(app::state(), app::handle(), artist_id, offset, TRACKS_PAGE_SIZE)
                    .await;

            let _ = qt.queue(move |mut obj| {
                if !obj.rust().tracks_requests.is_current(token) {
                    return;
                }
                obj.as_mut().set_loading(false);
                match result {
                    Ok(value) => {
                        let items = value.get("items").and_then(|v| v.as_array()).cloned().unwrap_or_default();
                        let page_len = items.len() as u32;
                        let start_index = obj.rust().tracks_rows.len();
                        let new_rows: Vec<Value> = items
                            .iter()
                            .enumerate()
                            .filter_map(|(i, it)| {
                                let mut track: TidalTrack = serde_json::from_value(unwrap_item(it)).ok()?;
                                track.backfill_artist();
                                Some(rows::track(start_index + i, &track))
                            })
                            .collect();
                        {
                            let mut rust = obj.as_mut().rust_mut();
                            rust.tracks_rows.extend(new_rows);
                            rust.tracks_offset += page_len;
                        }
                        let json = serde_json::to_string(&obj.rust().tracks_rows).unwrap_or_else(|_| "[]".into());
                        obj.as_mut().set_tracks_json(QString::from(&json));
                        obj.as_mut().set_has_more(page_len >= TRACKS_PAGE_SIZE);
                    }
                    Err(e) => {
                        obj.as_mut().set_has_more(false);
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }
            });
        });
    }

    pub fn load_library(mut self: Pin<&mut Self>, kind: &QString, user_id: i64) {
        {
            let mut rust = self.as_mut().rust_mut();
            rust.library_kind = kind.to_string();
            rust.library_user_id = user_id.max(0) as u64;
            rust.library_offset = 0;
            rust.library_items.clear();
        }
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        self.as_mut().set_has_more(false);
        self.as_mut().set_total(0);
        self.fetch_library_page();
    }

    pub fn load_more_library(mut self: Pin<&mut Self>) {
        if !*self.has_more() || *self.loading() {
            return;
        }
        self.as_mut().set_loading(true);
        self.fetch_library_page();
    }

    pub fn set_library_sort(mut self: Pin<&mut Self>, order: &QString, direction: &QString) {
        {
            let mut rust = self.as_mut().rust_mut();
            rust.library_order = order.to_string();
            rust.library_direction = direction.to_string();
            rust.library_offset = 0;
            rust.library_items.clear();
        }
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        self.fetch_library_page();
    }

    fn fetch_library_page(mut self: Pin<&mut Self>) {
        let token = self.as_mut().rust_mut().library_requests.start();
        let kind = self.rust().library_kind.clone();
        let user_id = self.rust().library_user_id;
        let offset = self.rust().library_offset;
        let order = self.rust().library_order.clone();
        let direction = self.rust().library_direction.clone();
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let outcome = fetch_library_kind(&kind, user_id, offset, LIBRARY_PAGE_SIZE, order, direction).await;

            let _ = qt.queue(move |mut obj| {
                if !obj.rust().library_requests.is_current(token) {
                    return;
                }
                obj.as_mut().set_loading(false);
                match outcome {
                    Ok((page_rows, total)) => {
                        let page_len = page_rows.len() as u32;
                        {
                            let mut rust = obj.as_mut().rust_mut();
                            rust.library_items.extend(page_rows);
                            rust.library_offset += page_len;
                        }
                        let json = serde_json::to_string(&obj.rust().library_items).unwrap_or_else(|_| "[]".into());
                        obj.as_mut().set_items_json(QString::from(&json));
                        obj.as_mut().set_total(total as i32);
                        let loaded = obj.rust().library_items.len() as u32;
                        obj.as_mut().set_has_more(page_len > 0 && loaded < total);
                    }
                    Err(e) => {
                        obj.as_mut().set_has_more(false);
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }
            });
        });
    }
}
