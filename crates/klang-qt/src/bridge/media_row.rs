//! One flattening of a TIDAL page section for every carousel and grid.
//!
//! `HomePageSection.items` is untyped JSON — TIDAL returns a different shape
//! per entity kind, and a different one again between the v1 and v2 endpoints
//! — so this is where it gets sniffed into uniform
//! `{id, title, subtitle, image, kind}` rows.
//!
//! `home.rs` and `viewall.rs` both render these; they had a byte-identical
//! copy each until the section-level handling drifted apart, so the whole
//! flattening lives here now. The credit row below is shared for the same
//! reason — the album page and the now-playing panel list the same thing.

use klang_core::tidal_api::{HomePageSection, TidalCredit};
use serde_json::{json, Value};

/// Navigation and promo chrome, not playable entities. `get_page_section`
/// (Explore) does not filter these itself, unlike `get_home_page`.
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

/// Pull `{text}` or a bare string out of a v2 text-info field.
fn text_info(v: &Value) -> Option<String> {
    v.as_str()
        .map(|s| s.to_string())
        .or_else(|| v.get("text").and_then(|t| t.as_str()).map(|s| s.to_string()))
}

/// Entity kind of one raw item: declared `_itemType`/`type` first, then the
/// section type, then field-shape sniffing — the same order
/// `TidalClient::parse_v2_section` uses.
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
        "VIDEO" => return "video",
        _ => {}
    }

    match section_type {
        "MIX_LIST" => return "mix",
        "ALBUM_LIST" => return "album",
        "PLAYLIST_LIST" => return "playlist",
        "ARTIST_LIST" => return "artist",
        "TRACK_LIST" => return "track",
        // A video's own `type` is its genre ("Music Video", "Live"), so the
        // section is the only thing that says these are videos and not
        // tracks — which is what the shape sniffing below would call them.
        "VIDEO_LIST" => return "video",
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
pub fn item_row(item: &Value, section_type: &str) -> Value {
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
        "album" | "track" | "video" => artist_name(item),
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
        // A video has no album to borrow a cover from; its own still is
        // `imageId`, and it is 16:9 rather than square.
        "video" => item.get("imageId").and_then(|v| v.as_str()),
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

    json!({
        "id": item_id(item),
        "title": title,
        "subtitle": subtitle,
        "image": image,
        "kind": kind,
    })
}

/// Turn API sections into the `{title, kind, items, apiPath}` shape QML binds
/// to. Drops navigation/promo sections and any section that ends up with no
/// rows (e.g. a v1 module type this bridge doesn't recognise at all).
/// `kind` on the section is the first item's kind — sections are carousels
/// of one entity type in practice; if a `MIXED_TYPES_LIST` slips through with
/// genuinely mixed content, each item still carries its own accurate `kind`
/// for QML to key off.
pub fn sections_to_json(sections: &[HomePageSection]) -> String {
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
            Some(json!({
                "title": s.title,
                "kind": kind,
                "items": items,
                // Only sections TIDAL paginates get a "View all" destination.
                "apiPath": s.api_path.clone().filter(|_| s.has_more),
            }))
        })
        .collect();

    serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into())
}

/// Flatten one credit role: TIDAL groups contributors by role
/// ("Producer", "Mixer", ...), which is how both the album page and the
/// now-playing credits panel list them.
pub fn credit_row(credit: &TidalCredit) -> Value {
    json!({
        "role": credit.credit_type,
        "contributors": credit
            .contributors
            .iter()
            .map(|c| c.name.clone())
            .collect::<Vec<_>>(),
    })
}
