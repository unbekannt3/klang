//! Home and Explore pages.
//!
//! TIDAL's home page is a list of horizontal carousels ("Individuelle Mixe",
//! "Kürzlich abgespielt", "Neue Alben-Vorschläge für dich", …). The facade
//! (`klang_core::api::pages`) hands back `HomePageSection`s whose `items`
//! field is deliberately untyped JSON — TIDAL's v1/v2 home-feed endpoints
//! return wildly different shapes per entity (mix/album/playlist/artist/
//! track) and the facade passes them through unparsed rather than force a
//! single struct on them (see the comment above `TidalMix` in
//! `tidal_api.rs`). This bridge is where that raw JSON finally gets sniffed
//! into a uniform `{id, title, subtitle, image, kind}` row so QML can pick a
//! card shape from `kind` without knowing TIDAL's wire format.
//!
//! Follows the shape of `library.rs`: properties for what QML binds to,
//! `#[qinvokable]` entry points that spawn onto `klang_core::runtime` and
//! queue results back with `CxxQtThread::queue`.

use crate::core as app;
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use klang_core::api::pages;
use klang_core::tidal_api::HomePageSection;
use serde_json::Value;
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
        #[qproperty(QString, sections_json)]
        #[qproperty(QString, explore_json)]
        type HomeController = super::HomeControllerRust;

        /// Load the personalized home feed: a JSON array of
        /// `{title, kind, items}` carousels, newest/most-relevant first —
        /// TIDAL's own ordering is trusted, nothing is resorted here.
        #[qinvokable]
        fn load_home(self: Pin<&mut HomeController>);

        /// Load the Explore page, in the same section shape as home.
        #[qinvokable]
        fn load_explore(self: Pin<&mut HomeController>);
    }

    impl cxx_qt::Threading for HomeController {}
}

#[derive(Default)]
pub struct HomeControllerRust {
    loading: bool,
    error: QString,
    sections_json: QString,
    explore_json: QString,
}

/// Section types that are navigation/promo chrome, not a carousel of
/// playable entities. Mirrors the filtering `TidalClient` already applies in
/// `get_home_page` / `get_home_page_more` / `parse_v1_module` — kept here too
/// because `get_page_section` (used for Explore) does none of that filtering
/// itself.
fn is_content_section(section_type: &str) -> bool {
    !matches!(
        section_type,
        "PAGE_LINKS_CLOUD"
            | "PAGE_LINKS"
            | "SHORTCUT_LIST"
            | "TEXT_BLOCK"
            | "SOCIAL"
            | "ARTICLE_LIST"
            | "FEATURED_PROMOTIONS"
    )
}

/// Pull `{text}` or a bare string out of a v2 "text info" field
/// (`titleTextInfo`, `subtitleTextInfo`, … — see `MixTextInfo` in
/// `tidal_api.rs`).
fn text_info(v: &Value) -> Option<String> {
    v.as_str()
        .map(|s| s.to_string())
        .or_else(|| v.get("text").and_then(|t| t.as_str()).map(|s| s.to_string()))
}

/// Classify one raw item's TIDAL entity kind from the fields it carries.
///
/// `HomePageSection.items` is untyped JSON, so there is no enum to match on.
/// `TidalClient::parse_v2_section` already solves this exact problem to pick
/// a *section* type (home_feed v2 wraps each item as `{type, data}` and
/// merges `type` into `data._itemType`); this reuses the same declared-type
/// check first, then falls back to the same shape-sniffing heuristic
/// (`mixType`/`mixImages` → mix, `uuid` → playlist, `cover`/`numberOfTracks`
/// → album, `picture` → artist, else track) for sections whose type doesn't
/// name a single kind (`MIXED_TYPES_LIST`, `MIXED_LIST`, or a v1 module type
/// passed through unmapped).
fn item_kind(item: &Value, section_type: &str) -> &'static str {
    let declared = item
        .get("_itemType")
        .or_else(|| item.get("type"))
        .and_then(|t| t.as_str())
        .unwrap_or("");
    match declared {
        "MIX" => return "mix",
        "ALBUM" => return "album",
        "PLAYLIST" => return "playlist",
        "ARTIST" => return "artist",
        "TRACK" => return "track",
        _ => {}
    }

    match section_type {
        "MIX_LIST" => return "mix",
        "ALBUM_LIST" => return "album",
        "PLAYLIST_LIST" => return "playlist",
        "ARTIST_LIST" => return "artist",
        "TRACK_LIST" => return "track",
        _ => {}
    }

    if item.get("mixType").is_some()
        || item.get("mixImages").is_some()
        || item.get("mixId").is_some()
    {
        "mix"
    } else if item.get("uuid").is_some() {
        "playlist"
    } else if item.get("cover").is_some() || item.get("numberOfTracks").is_some() {
        "album"
    } else if item.get("picture").is_some() && item.get("cover").is_none() {
        "artist"
    } else {
        "track"
    }
}

/// `artist.name` (`TidalArtist`), falling back to the first entry of a plural
/// `artists` array — endpoints differ in which of the two they populate, same
/// as `TidalTrack::backfill_artist` handles for typed tracks. Also covers the
/// v2 MIX artist ref shape (`MixArtistRef.artistName`).
fn artist_name(item: &Value) -> Option<String> {
    item.get("artist")
        .and_then(|a| a.get("name").or_else(|| a.get("artistName")))
        .and_then(|n| n.as_str())
        .map(|s| s.to_string())
        .or_else(|| {
            item.get("artists")
                .and_then(|a| a.as_array())
                .and_then(|a| a.first())
                .and_then(|a| a.get("name"))
                .and_then(|n| n.as_str())
                .map(|s| s.to_string())
        })
}

/// Numeric `id` (album/artist/track), string `id` (the documented `TidalMix`
/// shape), `uuid` (playlist), or `mixId` — the key `section_dedup_key` in
/// `tidal_api.rs` already falls back to for mixes when `id`/`uuid` aren't a
/// match, evidence the real payload doesn't always agree with `TidalMix`.
fn item_id(item: &Value) -> String {
    if let Some(id) = item.get("id") {
        if let Some(n) = id.as_u64() {
            return n.to_string();
        }
        if let Some(s) = id.as_str() {
            return s.to_string();
        }
    }
    item.get("uuid")
        .and_then(|v| v.as_str())
        .or_else(|| item.get("mixId").and_then(|v| v.as_str()))
        .unwrap_or_default()
        .to_string()
}

/// Flatten one raw item into `{id, title, subtitle, image, kind}`. `image` is
/// the raw TIDAL image UUID, passed through unchanged — except for `mix`,
/// where the only image the documented `TidalMix` shape carries
/// (`mixImages[].url`) is already a full URL, not a bare UUID; that is
/// passed through as-is too rather than guessing at a UUID that may not
/// exist in the real payload.
fn item_row(item: &Value, section_type: &str) -> Value {
    let kind = item_kind(item, section_type);

    let title = match kind {
        "artist" => item.get("name").and_then(|v| v.as_str()).map(String::from),
        "mix" => item
            .get("titleTextInfo")
            .and_then(text_info)
            .or_else(|| item.get("title").and_then(|v| v.as_str()).map(String::from)),
        _ => item.get("title").and_then(|v| v.as_str()).map(String::from),
    }
    .unwrap_or_default();

    let subtitle = match kind {
        "mix" => item
            .get("subtitleTextInfo")
            .and_then(text_info)
            .or_else(|| item.get("shortSubtitleTextInfo").and_then(text_info))
            .or_else(|| item.get("subTitle").and_then(|v| v.as_str()).map(String::from)),
        "album" | "track" => artist_name(item),
        "playlist" => item
            .get("creator")
            .and_then(|c| c.get("name"))
            .and_then(|n| n.as_str())
            .map(String::from)
            .or_else(|| {
                item.get("numberOfTracks")
                    .and_then(|v| v.as_u64())
                    .map(|n| format!("{} tracks", n))
            }),
        _ => None,
    }
    .unwrap_or_default();

    let image = match kind {
        "artist" => item.get("picture").and_then(|v| v.as_str()),
        "playlist" => item
            .get("squareImage")
            .and_then(|v| v.as_str())
            .or_else(|| item.get("image").and_then(|v| v.as_str())),
        "album" => item.get("cover").and_then(|v| v.as_str()),
        "track" => item
            .get("album")
            .and_then(|a| a.get("cover"))
            .and_then(|v| v.as_str())
            .or_else(|| item.get("imageId").and_then(|v| v.as_str())),
        "mix" => item
            .get("mixImages")
            .and_then(|v| v.as_array())
            .and_then(|a| a.first())
            .and_then(|img| img.get("url"))
            .and_then(|v| v.as_str())
            .or_else(|| {
                item.get("artist")
                    .and_then(|a| a.get("artistImage"))
                    .and_then(|ai| ai.get("imageUuid"))
                    .and_then(|v| v.as_str())
            }),
        _ => None,
    }
    .unwrap_or_default();

    serde_json::json!({
        "id": item_id(item),
        "title": title,
        "subtitle": subtitle,
        "image": image,
        "kind": kind,
    })
}

/// Turn API sections into the `{title, kind, items}` shape QML binds to.
/// Drops navigation/promo sections and any section that ends up with no
/// rows (e.g. a v1 module type this bridge doesn't recognise at all).
/// `kind` on the section is the first item's kind — sections are carousels
/// of one entity type in practice; if a `MIXED_TYPES_LIST` slips through with
/// genuinely mixed content, each item still carries its own accurate `kind`
/// for QML to key off.
fn sections_to_json(sections: &[HomePageSection]) -> String {
    let rows: Vec<Value> = sections
        .iter()
        .filter(|s| is_content_section(&s.section_type) && !s.title.trim().is_empty())
        .filter_map(|s| {
            let items: Vec<Value> = s
                .items
                .as_array()
                .map(|arr| arr.iter().map(|it| item_row(it, &s.section_type)).collect())
                .unwrap_or_default();
            if items.is_empty() {
                return None;
            }
            let kind = items
                .first()
                .and_then(|it| it.get("kind"))
                .and_then(|k| k.as_str())
                .unwrap_or("track");
            Some(serde_json::json!({
                "title": s.title,
                "kind": kind,
                "items": items,
            }))
        })
        .collect();

    serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into())
}

/// `pages::get_home_page` returns `HomePageCached { home, is_stale }` with
/// private fields (only the type itself is `pub`) — there's no accessor, and
/// adding one is out of scope here (klang-core is off-limits for this
/// change). It still derives `Serialize`, which isn't subject to Rust's field
/// privacy, so round-tripping through `serde_json::Value` is the way to reach
/// `.home` from outside the defining module.
fn sections_from_cached(cached: &pages::HomePageCached) -> Vec<HomePageSection> {
    serde_json::to_value(cached)
        .ok()
        .and_then(|v| v.get("home").and_then(|h| h.get("sections")).cloned())
        .and_then(|s| serde_json::from_value(s).ok())
        .unwrap_or_default()
}

impl qobject::HomeController {
    pub fn load_home(mut self: Pin<&mut Self>) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let result = pages::get_home_page(app::state(), app::handle(), None).await;

            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_loading(false);
                match result {
                    Ok(cached) => {
                        let sections = sections_from_cached(&cached);
                        obj.as_mut()
                            .set_sections_json(QString::from(&sections_to_json(&sections)));
                    }
                    Err(e) => {
                        obj.as_mut().set_sections_json(QString::from("[]"));
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }
            });
        });
    }

    pub fn load_explore(mut self: Pin<&mut Self>) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            // No dedicated "explore" facade function exists — `pages/explore`
            // is the same endpoint `TidalClient::get_home_page`'s v1 fallback
            // and `debug_home_page_raw` already fetch for it. Routed through
            // the generic `get_page_section`, which returns the same
            // `HomePageResponse` shape as home.
            let result = pages::get_page_section(
                app::state(),
                app::handle(),
                "pages/explore".to_string(),
            )
            .await;

            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_loading(false);
                match result {
                    Ok(page) => {
                        obj.as_mut()
                            .set_explore_json(QString::from(&sections_to_json(&page.sections)));
                    }
                    Err(e) => {
                        obj.as_mut().set_explore_json(QString::from("[]"));
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }
            });
        });
    }
}
