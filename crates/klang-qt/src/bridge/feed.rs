//! The activity feed: new releases from artists and playlists you follow.

use crate::bridge::RequestSeq;
use crate::core as app;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use klang_core::api::feed;
use klang_core::tidal_api::{FeedItem, FeedItemKind};
use serde_json::Value;
use std::collections::HashMap;
use std::pin::Pin;
use std::time::{SystemTime, UNIX_EPOCH};

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
        #[qproperty(QString, items_json)]
        type FeedController = super::FeedControllerRust;

        /// A JSON array of `{date, label, items}` day groups, newest first.
        #[qinvokable]
        fn load(self: Pin<&mut FeedController>, user_id: i64);

        /// Drop the server's cached unread count. Fired once the page has
        /// been shown, independent of whether `load` (or this) has finished —
        /// mirrors sone's separate effect for the same reason: opening the
        /// page is what marks it seen.
        #[qinvokable]
        fn mark_seen(self: Pin<&mut FeedController>, user_id: i64);
    }

    impl cxx_qt::Threading for FeedController {}
}

#[derive(Default)]
pub struct FeedControllerRust {
    loading: bool,
    error: QString,
    items_json: QString,
    requests: RequestSeq,
}

const MONTH_NAMES: [&str; 12] = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
];

/// Days since the Unix epoch for a UTC calendar date (Howard Hinnant's
/// `days_from_civil`). Pulled in whole rather than a date crate: this is the
/// one subtraction the day-grouping needs, and neither klang-core nor
/// klang-qt otherwise depends on chrono/time.
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

fn today_epoch_day() -> i64 {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    (secs / 86_400) as i64
}

/// `occurredAt` is always midnight UTC (day granularity, per
/// `flatten_feed_activity`'s source), so slicing the first 10 characters is
/// enough to read the calendar date without a time-zone conversion.
fn parse_date(occurred_at: &str) -> Option<(i64, i64, i64)> {
    let s = occurred_at.get(0..10)?;
    let y = s.get(0..4)?.parse().ok()?;
    let m = s.get(5..7)?.parse().ok()?;
    let d = s.get(8..10)?.parse().ok()?;
    Some((y, m, d))
}

/// Readable heading for one day bucket, or the raw timestamp if it doesn't parse.
fn day_label(occurred_at: &str, today: i64) -> String {
    match parse_date(occurred_at) {
        Some((y, m, d)) => match today - days_from_civil(y, m, d) {
            delta if delta <= 0 => "Today".to_string(),
            1 => "Yesterday".to_string(),
            _ => format!("{} {}, {}", MONTH_NAMES[(m - 1) as usize], d, y),
        },
        None => occurred_at.to_string(),
    }
}

/// Pull `{text}` or a bare string out of a v2 text-info field, same shape
/// `home.rs::text_info` reads for mixes.
fn text_info(v: &Value) -> Option<String> {
    v.as_str()
        .map(String::from)
        .or_else(|| v.get("text").and_then(|t| t.as_str()).map(String::from))
}

/// Numeric `id` (album) or string `id`/`mixId` (mix) — the raw payload uses
/// whichever its own entity type does.
fn item_id(item: &Value) -> String {
    if let Some(id) = item.get("id") {
        if let Some(n) = id.as_u64() {
            return n.to_string();
        }
        if let Some(s) = id.as_str() {
            return s.to_string();
        }
    }
    item.get("mixId")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string()
}

/// "Album by Artist" / "EP by Artist" / "Single by Artist", falling back to
/// bare artist names. Mirrors sone's `feedSubtitle` for the album branch —
/// the only place feed rows carry a type worth naming.
fn album_subtitle(item: &Value) -> String {
    let artists = item
        .get("artists")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|a| a.get("name").and_then(|n| n.as_str()))
                .collect::<Vec<_>>()
                .join(", ")
        })
        .unwrap_or_default();

    let raw_type = item.get("type").and_then(|v| v.as_str()).unwrap_or("");
    let label = if raw_type == "EP" {
        "EP".to_string()
    } else if let Some(first) = raw_type.chars().next() {
        first.to_uppercase().collect::<String>() + &raw_type[first.len_utf8()..].to_lowercase()
    } else {
        String::new()
    };

    if !label.is_empty() && !artists.is_empty() {
        format!("{} by {}", label, artists)
    } else {
        artists
    }
}

/// One `{id, title, subtitle, image, kind, seen}` row for a `MediaCard`.
fn feed_item_row(entry: &FeedItem) -> Value {
    let item = &entry.item;

    let (kind, title, subtitle, image) = match entry.kind {
        FeedItemKind::Album => (
            "album",
            item.get("title").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
            album_subtitle(item),
            item.get("cover").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
        ),
        FeedItemKind::Mix => (
            "mix",
            item.get("titleTextInfo")
                .and_then(text_info)
                .or_else(|| item.get("title").and_then(|v| v.as_str()).map(String::from))
                .unwrap_or_default(),
            item.get("subtitleTextInfo")
                .and_then(text_info)
                .or_else(|| item.get("shortSubtitleTextInfo").and_then(text_info))
                .unwrap_or_default(),
            item.get("mixImages")
                .and_then(|v| v.as_array())
                .and_then(|a| a.first())
                .and_then(|img| img.get("url"))
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
        ),
        // A payload kind this backend doesn't recognise yet (TIDAL adding a
        // new followableActivity type). Best-effort generic fields rather
        // than a blank card; FeedPage.qml still keeps it inert on click.
        FeedItemKind::Unknown => (
            "unknown",
            item.get("title").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
            item.get("subTitle")
                .or_else(|| item.get("description"))
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
            item.get("cover")
                .or_else(|| item.get("squareImage"))
                .or_else(|| item.get("image"))
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
        ),
    };

    serde_json::json!({
        "id": item_id(item),
        "title": title,
        "subtitle": subtitle,
        "image": image,
        "kind": kind,
        "seen": entry.seen,
    })
}

/// Bucket feed items by calendar day, in the order they arrive (TIDAL already
/// returns the feed newest-first, so this does not re-sort). A `HashMap`
/// keyed by date plus a separate order list keeps same-day entries together
/// even if the feed ever interleaves two days, without assuming adjacency.
fn group_by_day(items: &[FeedItem]) -> Vec<Value> {
    let today = today_epoch_day();
    let mut order: Vec<String> = Vec::new();
    let mut buckets: HashMap<String, (String, Vec<Value>)> = HashMap::new();

    for entry in items {
        let date_key = entry
            .occurred_at
            .get(0..10)
            .unwrap_or(&entry.occurred_at)
            .to_string();
        let row = feed_item_row(entry);

        match buckets.get_mut(&date_key) {
            Some((_, rows)) => rows.push(row),
            None => {
                let label = day_label(&entry.occurred_at, today);
                order.push(date_key.clone());
                buckets.insert(date_key, (label, vec![row]));
            }
        }
    }

    order
        .into_iter()
        .map(|date| {
            let (label, rows) = buckets.remove(&date).unwrap_or_default();
            serde_json::json!({ "date": date, "label": label, "items": rows })
        })
        .collect()
}

impl qobject::FeedController {
    pub fn load(mut self: Pin<&mut Self>, user_id: i64) {
        let token = self.as_mut().rust_mut().requests.start();
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let result = feed::get_feed(app::state(), user_id as u64).await;

            let _ = qt.queue(move |mut obj| {
                if !obj.rust().requests.is_current(token) {
                    return;
                }
                obj.as_mut().set_loading(false);
                match result {
                    Ok(response) => {
                        let groups = group_by_day(&response.items);
                        let json = serde_json::to_string(&groups).unwrap_or_else(|_| "[]".into());
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

    pub fn mark_seen(self: Pin<&mut Self>, user_id: i64) {
        klang_core::runtime::spawn(async move {
            let result = feed::mark_feed_seen(app::state(), user_id as u64).await;
            if let Err(e) = result {
                log::warn!("[feed] mark_seen failed: {}", e);
            }
        });
    }
}
