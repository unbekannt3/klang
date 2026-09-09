//! Playback control and the now-playing state QML binds to.

use crate::bridge::RequestSeq;
use crate::core as app;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use crate::queue::{Entry, Queue, Repeat};
use klang_core::api::{pages, playback, utility};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(bool, playing)]
        #[qproperty(bool, busy)]
        #[qproperty(f32, position_secs)]
        #[qproperty(f32, duration_secs)]
        #[qproperty(QString, title)]
        #[qproperty(QString, artist)]
        #[qproperty(QString, cover)]
        #[qproperty(i64, artist_id)]
        #[qproperty(i64, album_id)]
        #[qproperty(QString, quality)]
        /// The tier TIDAL served — LOW/HIGH/LOSSLESS/HI_RES_LOSSLESS — kept
        /// apart from `quality`, which is the bit depth and sample rate.
        #[qproperty(QString, quality_tier)]
        #[qproperty(QString, error)]
        #[qproperty(i64, track_id)]
        #[qproperty(bool, shuffle)]
        /// 0 off, 1 all, 2 one.
        #[qproperty(i32, repeat)]
        #[qproperty(f32, volume)]
        #[qproperty(QString, queue_json)]
        #[qproperty(QString, history_json)]
        /// Human-readable name of what is playing, e.g. a playlist title.
        #[qproperty(QString, source_label)]
        #[qproperty(QString, source)]
        type PlayerController = super::PlayerControllerRust;

        /// Resolve the stream and start playing. `duration` seeds the progress
        /// bar before the pipeline reports anything.
        #[qinvokable]
        fn play(
            self: Pin<&mut PlayerController>,
            track_id: i64,
            title: &QString,
            artist: &QString,
            duration: f32,
            cover: &QString,
        );

        /// Pause if playing, resume if paused.
        #[qinvokable]
        fn toggle(self: Pin<&mut PlayerController>);

        #[qinvokable]
        fn stop(self: Pin<&mut PlayerController>);

        #[qinvokable]
        fn seek(self: Pin<&mut PlayerController>, position_secs: f32);

        #[qinvokable]
        fn set_output_volume(self: Pin<&mut PlayerController>, level: f32);

        /// Replace the queue with `tracks_json` and start at `index`.
        #[qinvokable]
        fn play_context(
            self: Pin<&mut PlayerController>,
            tracks_json: &QString,
            index: i32,
            source: &QString,
        );

        #[qinvokable]
        fn next(self: Pin<&mut PlayerController>);

        #[qinvokable]
        fn previous(self: Pin<&mut PlayerController>);

        /// Enqueue ahead of the context.
        #[qinvokable]
        fn play_next(self: Pin<&mut PlayerController>, track_json: &QString);

        #[qinvokable]
        fn enqueue(self: Pin<&mut PlayerController>, track_json: &QString);

        /// Jump to an upcoming entry. `manual` picks which list `index` is in.
        #[qinvokable]
        fn jump_to(self: Pin<&mut PlayerController>, index: i32, manual: bool);

        /// Append what a paginated source has loaded since playback started.
        /// A no-op unless the queue still comes from `source`.
        #[qinvokable]
        fn extend_context(
            self: Pin<&mut PlayerController>,
            tracks_json: &QString,
            source: &QString,
        );

        #[qinvokable]
        fn remove_queued(self: Pin<&mut PlayerController>, index: i32);

        #[qinvokable]
        fn clear_queue(self: Pin<&mut PlayerController>);

        #[qinvokable]
        fn toggle_shuffle(self: Pin<&mut PlayerController>);

        #[qinvokable]
        fn toggle_repeat(self: Pin<&mut PlayerController>);

        #[qinvokable]
        fn toggle_mute(self: Pin<&mut PlayerController>);

        /// Start the position poll and subscribe to core events. Call once.
        #[qinvokable]
        fn attach(self: Pin<&mut PlayerController>);
    }

    impl cxx_qt::Threading for PlayerController {}
}

pub struct PlayerControllerRust {
    playing: bool,
    busy: bool,
    position_secs: f32,
    duration_secs: f32,
    title: QString,
    artist: QString,
    cover: QString,
    artist_id: i64,
    album_id: i64,
    quality: QString,
    quality_tier: QString,
    error: QString,
    track_id: i64,
    shuffle: bool,
    repeat: i32,
    volume: f32,
    queue_json: QString,
    history_json: QString,
    source_label: QString,
    source: QString,
    attached: bool,
    queue: Mutex<Queue>,
    /// Restored when unmuting.
    volume_before_mute: f32,
    /// qid of the track currently prerolled for gapless, matched against the
    /// `track-advanced` event that confirms the pipeline switched to it.
    armed_qid: String,
    /// Monotonic source for `armed_qid`, so two prerolls in a row never collide.
    next_arm_seq: u64,
    /// Set on every position tick and queue mutation, cleared by the debounced
    /// save in `attach`.
    queue_dirty: bool,
    /// Whether `play_url` has ever run this session; `toggle` uses this to
    /// tell a real pause from a start-up restore with nothing loaded yet.
    pipeline_loaded: bool,
    /// Position to seek to once the in-flight `play()` reports it started —
    /// set by `toggle`'s cold-start path, consumed in `play`.
    pending_seek: Option<f32>,
    /// Clicking track A then B leaves two `play_tidal_track` tasks racing;
    /// only the newest may write quality, `playing` or the metadata push.
    plays: RequestSeq,
    /// `playing`, readable from the position poll's own thread so it can skip
    /// a tick without waking the GUI thread to find out nothing is playing.
    /// Written only through `set_playback_active`.
    playback_active: Arc<AtomicBool>,
}

impl Default for PlayerControllerRust {
    fn default() -> Self {
        Self {
            playing: false,
            busy: false,
            position_secs: 0.0,
            duration_secs: 0.0,
            title: QString::default(),
            artist: QString::default(),
            cover: QString::default(),
            artist_id: 0,
            album_id: 0,
            quality: QString::default(),
            quality_tier: QString::default(),
            error: QString::default(),
            track_id: 0,
            shuffle: false,
            repeat: 0,
            volume: 1.0,
            queue_json: QString::from("[]"),
            history_json: QString::from("[]"),
            source_label: QString::default(),
            source: QString::default(),
            attached: false,
            queue: Mutex::new(Queue::default()),
            volume_before_mute: 1.0,
            armed_qid: String::new(),
            next_arm_seq: 0,
            queue_dirty: false,
            pipeline_loaded: false,
            pending_seek: None,
            plays: RequestSeq::default(),
            playback_active: Arc::new(AtomicBool::new(false)),
        }
    }
}

/// Reports the sample rate and bit depth TIDAL actually served, so the badge
/// tells the truth rather than what was requested.
fn quality_label(info: &klang_core::tidal_api::StreamInfo) -> String {
    match (info.bit_depth, info.sample_rate) {
        (Some(bits), Some(rate)) => format!("{bits}-bit {:.1} kHz", rate as f64 / 1000.0),
        _ => info
            .audio_quality
            .clone()
            .unwrap_or_else(|| "unknown".to_string()),
    }
}

/// Same UUID-to-CDN mapping as `CoverArt.qml`'s `url()`; MPRIS needs a real
/// URI, not the bare TIDAL image UUID the rest of the UI passes around.
fn art_url(cover: &str) -> String {
    if cover.is_empty() {
        return String::new();
    }
    if cover.starts_with("http") {
        return cover.to_string();
    }
    let path = cover.replace('-', "/");
    format!("https://resources.tidal.com/images/{path}/1280x1280.jpg")
}

fn push_playback_status(is_playing: bool, position_secs: f64) {
    let _ = playback::update_mpris_playback_status(app::state(), is_playing, Some(position_secs));
}

fn push_shuffle(enabled: bool) {
    let _ = playback::update_mpris_shuffle(app::state(), enabled);
}

fn push_loop_status(repeat: Repeat) {
    let _ = playback::update_mpris_loop_status(app::state(), repeat.as_i32() as u8);
}

/// On-disk shape of a saved queue: `{"queue": <Queue's own serde fields>,
/// "position_secs": <last known playback position>}`.
#[derive(Serialize, Deserialize)]
struct QueueSnapshot {
    queue: Queue,
    position_secs: f32,
}

impl qobject::PlayerController {
    pub fn play(
        mut self: Pin<&mut Self>,
        track_id: i64,
        title: &QString,
        artist: &QString,
        duration: f32,
        cover: &QString,
    ) {
        self.as_mut().set_busy(true);
        self.as_mut().set_error(QString::from(""));
        self.as_mut().set_title(title.clone());
        self.as_mut().set_artist(artist.clone());
        self.as_mut().set_cover(cover.clone());
        // A card played on its own carries no ids, so the bar's links go
        // quiet rather than pointing at whatever played before.
        self.as_mut().set_artist_id(0);
        self.as_mut().set_album_id(0);
        self.as_mut().set_duration_secs(duration);
        self.as_mut().set_position_secs(0.0);
        self.as_mut().set_track_id(track_id);
        self.as_mut().rust_mut().pipeline_loaded = true;
        let token = self.as_mut().rust_mut().plays.start();
        self.publish_metadata();
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            // use_track_gain: true — a hand-picked track is not album playback,
            // so track gain is the right normalization reference.
            let result = playback::play_tidal_track(app::state(), track_id as u64, true).await;
            let _ = qt.queue(move |mut obj| {
                if !obj.rust().plays.is_current(token) {
                    return; // a newer play() owns the display and the pipeline
                }
                obj.as_mut().set_busy(false);
                match result {
                    Ok(info) => {
                        obj.as_mut().set_quality(QString::from(&quality_label(&info)));
                        obj.as_mut().set_quality_tier(QString::from(
                            &info.audio_quality.clone().unwrap_or_default(),
                        ));
                        obj.as_mut().set_playback_active(true);
                        obj.as_mut().publish_metadata();
                        push_playback_status(true, 0.0);
                        // The queue-driven callers (start/gapless/resume) set this
                        // before play() resolves; an ad-hoc play() leaves it None.
                        if let Some(pos) = obj.as_mut().rust_mut().pending_seek.take() {
                            let qt2 = obj.qt_thread();
                            klang_core::runtime::spawn(async move {
                                // play_url just returned; the pipeline is still
                                // negotiating caps and is not reliably seekable yet.
                                tokio::time::sleep(std::time::Duration::from_millis(400)).await;
                                let _ = qt2.queue(move |mut obj| {
                                    // Another track may have started during
                                    // the wait; seeking it to this position
                                    // would be worse than not seeking at all.
                                    if obj.rust().plays.is_current(token) {
                                        obj.as_mut().seek(pos);
                                    }
                                });
                            });
                        }
                        obj.as_mut().on_queue_changed();
                    }
                    Err(e) => {
                        obj.as_mut().set_playback_active(false);
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                        push_playback_status(false, 0.0);
                    }
                }
            });
        });
    }

    pub fn toggle(mut self: Pin<&mut Self>) {
        if !self.rust().pipeline_loaded {
            // Restored at start-up: the display shows the last track but
            // nothing was ever loaded into the pipeline, so resume_track has
            // nothing to resume — do a real load and carry the saved position.
            let restored = self.rust().queue.lock().unwrap().current().cloned();
            let saved_position = *self.position_secs();
            if let Some(entry) = restored {
                if saved_position > 0.5 {
                    self.as_mut().rust_mut().pending_seek = Some(saved_position);
                }
                self.start(entry);
            }
            return;
        }

        let want_play = !*self.playing();
        self.as_mut().set_playback_active(want_play);
        push_playback_status(want_play, *self.position_secs() as f64);
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let result = if want_play {
                playback::resume_track(app::state()).await
            } else {
                playback::pause_track(app::state()).await
            };
            if let Err(e) = result {
                let msg = e.to_string();
                let _ = qt.queue(move |mut obj| {
                    // The pipeline refused, so put the button back where it was.
                    obj.as_mut().set_playback_active(!want_play);
                    push_playback_status(!want_play, 0.0);
                    obj.as_mut().set_error(QString::from(&msg));
                });
            }
        });
    }

    pub fn stop(mut self: Pin<&mut Self>) {
        self.as_mut().set_playback_active(false);
        self.as_mut().set_position_secs(0.0);
        self.as_mut().rust_mut().queue_dirty = true;
        // Nothing is going to play next right now; drop whatever was prerolled.
        self.as_mut().rust_mut().armed_qid.clear();
        let _ = playback::clear_next_track(app::state());
        klang_core::runtime::spawn(async move {
            let _ = playback::stop_track(app::state()).await;
        });
    }

    pub fn seek(mut self: Pin<&mut Self>, position_secs: f32) {
        self.as_mut().set_position_secs(position_secs);
        klang_core::runtime::spawn(async move {
            let _ = playback::seek_track(app::state(), position_secs).await;
        });
    }

    pub fn set_output_volume(mut self: Pin<&mut Self>, level: f32) {
        self.as_mut().set_volume(level);
        let _ = playback::set_volume(app::state(), level);
    }

    pub fn attach(mut self: Pin<&mut Self>) {
        // Not a Q_PROPERTY — QML has no business seeing it, so it lives on the
        // Rust side and is reached through CxxQtType.
        if self.rust().attached {
            return;
        }
        self.as_mut().rust_mut().attached = true;
        self.as_mut().restore_queue();

        // Position poll. The pipeline is the source of truth for where we are;
        // 500 ms is the cadence the React UI used. While paused the tick is
        // dropped here rather than in a queued closure — waking the GUI
        // thread twice a second only to find nothing is playing is waste.
        let qt = self.qt_thread();
        let active = self.rust().playback_active.clone();
        klang_core::runtime::spawn(async move {
            let mut tick = tokio::time::interval(std::time::Duration::from_millis(500));
            loop {
                tick.tick().await;
                if !active.load(Ordering::Relaxed) {
                    continue;
                }
                let Ok(pos) = playback::get_playback_position(app::state()) else {
                    continue;
                };
                let _ = qt.queue(move |mut obj| {
                    obj.as_mut().set_position_secs(pos);
                    obj.as_mut().rust_mut().queue_dirty = true;
                });
            }
        });

        // Debounced queue save: the position tick above marks the snapshot
        // dirty every 500 ms while playing, but this flushes it to disk at
        // most once per interval, so resume never falls far behind without
        // writing the state file on every tick.
        let qt = self.qt_thread();
        klang_core::runtime::spawn(async move {
            let mut tick = tokio::time::interval(std::time::Duration::from_secs(5));
            loop {
                tick.tick().await;
                let _ = qt.queue(|mut obj| obj.as_mut().flush_queue_if_dirty());
            }
        });

        // Core events. `audio-error` is the one the user must see; `track-
        // advanced` is the gapless boundary firing without a `track-finished`
        // (concat switched branches on its own); the rest of the catalogue
        // lands here as the bridge grows.
        let qt = self.qt_thread();
        klang_core::runtime::spawn(async move {
            let mut events = app::subscribe();
            while let Ok(event) = events.recv().await {
                match event.name.as_str() {
                    "track-finished" => {
                        let _ = qt.queue(|mut obj| {
                            let next = obj.rust().queue.lock().unwrap().advance(true);
                            match next {
                                Some(entry) => obj.as_mut().start(entry),
                                None => {
                                    obj.as_mut().set_playback_active(false);
                                    obj.as_mut().set_position_secs(0.0);
                                    obj.as_mut().rust_mut().queue_dirty = true;
                                    push_playback_status(false, 0.0);
                                    obj.start_autoplay_radio();
                                }
                            }
                        });
                    }
                    "track-advanced" => {
                        let qid = event
                            .payload
                            .get("qid")
                            .and_then(|v| v.as_str())
                            .map(str::to_string);
                        let _ = qt.queue(move |mut obj| obj.as_mut().on_gapless_advanced(qid));
                    }
                    "audio-error" => {
                        let msg = event
                            .payload
                            .get("message")
                            .and_then(|v| v.as_str())
                            .unwrap_or("playback failed")
                            .to_string();
                        let _ = qt.queue(move |mut obj| {
                            obj.as_mut().set_playback_active(false);
                            obj.as_mut().set_error(QString::from(&msg));
                            push_playback_status(false, 0.0);
                        });
                    }
                    // Media keys, the tray menu and any MPRIS client all
                    // arrive as these events; without handling them the
                    // D-Bus interface is publish-only.
                    "tray:toggle-play" => {
                        let _ = qt.queue(|obj| obj.toggle());
                    }
                    "mpris:play" => {
                        let _ = qt.queue(|mut obj| {
                            if !*obj.as_mut().playing() {
                                obj.toggle();
                            }
                        });
                    }
                    "mpris:pause" => {
                        let _ = qt.queue(|mut obj| {
                            if *obj.as_mut().playing() {
                                obj.toggle();
                            }
                        });
                    }
                    "mpris:stop" => {
                        let _ = qt.queue(|obj| obj.stop());
                    }
                    "tray:next-track" => {
                        let _ = qt.queue(|obj| obj.next());
                    }
                    "tray:prev-track" => {
                        let _ = qt.queue(|obj| obj.previous());
                    }
                    "mpris:seek" => {
                        // Relative, unlike set-position.
                        if let Some(offset) = event.payload.as_f64() {
                            let _ = qt.queue(move |mut obj| {
                                let target = (*obj.as_mut().position_secs() + offset as f32).max(0.0);
                                obj.seek(target);
                            });
                        }
                    }
                    "mpris:set-position" => {
                        if let Some(secs) = event.payload.as_f64() {
                            let _ = qt.queue(move |obj| obj.seek(secs as f32));
                        }
                    }
                    "mpris:set-volume" => {
                        if let Some(level) = event.payload.as_f64() {
                            let _ = qt.queue(move |obj| obj.set_output_volume(level as f32));
                        }
                    }
                    "mpris:set-shuffle" => {
                        if let Some(on) = event.payload.as_bool() {
                            let _ = qt.queue(move |mut obj| {
                                if *obj.as_mut().shuffle() != on {
                                    obj.toggle_shuffle();
                                }
                            });
                        }
                    }
                    "mpris:set-loop-status" => {
                        if let Some(mode) = event.payload.as_str().map(str::to_string) {
                            let _ = qt.queue(move |obj| obj.apply_loop_status(&mode));
                        }
                    }
                    _ => {}
                }
            }
        });
    }

    /// Apply an MPRIS `LoopStatus` string. Unknown values are ignored rather
    /// than treated as "None" — a client sending something odd should not
    /// silently turn repeat off.
    fn apply_loop_status(mut self: Pin<&mut Self>, mode: &str) {
        let repeat = match mode {
            "None" => Repeat::Off,
            "Track" => Repeat::One,
            "Playlist" => Repeat::All,
            _ => return,
        };
        self.as_mut().rust_mut().queue.lock().unwrap().set_repeat(repeat);
        self.as_mut().set_repeat(repeat.as_i32());
        push_loop_status(repeat);
        self.on_queue_changed();
    }
}

/// Parse one row from `rows.rs` into a queue entry.
fn entry_from_json(value: &serde_json::Value) -> Option<Entry> {
    Some(Entry {
        id: value.get("id")?.as_i64()?,
        title: value.get("title").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
        artist: value.get("artist").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
        duration: value.get("duration").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32,
        album: value.get("album").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
        track_mix: value.get("trackMix").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
        cover: value.get("cover").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
        artist_id: value.get("artistId").and_then(|v| v.as_i64()).unwrap_or_default(),
        album_id: value.get("albumId").and_then(|v| v.as_i64()).unwrap_or_default(),
    })
}

fn entries_from_json(json: &str) -> Vec<Entry> {
    serde_json::from_str::<serde_json::Value>(json)
        .ok()
        .and_then(|v| v.as_array().cloned())
        .map(|rows| rows.iter().filter_map(entry_from_json).collect())
        .unwrap_or_default()
}

impl qobject::PlayerController {
    /// Publish what is queued, manual entries first, so QML can render one list.
    fn publish_queue(mut self: Pin<&mut Self>) {
        let (json, history, source) = {
            let queue = self.rust().queue.lock().unwrap();
            let rows: Vec<serde_json::Value> = queue
                .manual()
                .iter()
                .map(|e| serde_json::json!({
                    "id": e.id, "title": e.title, "artist": e.artist,
                    "duration": e.duration, "cover": e.cover, "manual": true,
                }))
                .chain(queue.upcoming().iter().map(|e| serde_json::json!({
                    "id": e.id, "title": e.title, "artist": e.artist,
                    "duration": e.duration, "cover": e.cover, "manual": false,
                })))
                .collect();
            let history: Vec<serde_json::Value> = queue
                .history()
                .iter()
                .rev()
                .map(|e| serde_json::json!({
                    "id": e.id, "title": e.title, "artist": e.artist,
                    "duration": e.duration, "cover": e.cover,
                }))
                .collect();
            (
                serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into()),
                serde_json::to_string(&history).unwrap_or_else(|_| "[]".into()),
                queue.source().to_string(),
            )
        };
        self.as_mut().set_queue_json(QString::from(&json));
        self.as_mut().set_history_json(QString::from(&history));
        self.as_mut().set_source(QString::from(&source));
    }

    /// Push what is currently loaded to MPRIS and Discord RPC. Reads the
    /// Q_PROPERTYs rather than taking an `Entry`, so `play()` and the gapless
    /// hand-off (which never builds one) share this one path.
    fn publish_metadata(&self) {
        // The album name lives on the queue entry rather than on a
        // Q_PROPERTY: play() is also called ad-hoc for a single card, where
        // there is no album to show.
        let track_id = *self.track_id();
        let album = self
            .rust()
            .queue
            .lock()
            .unwrap()
            .current()
            .filter(|entry| entry.id == track_id)
            .map(|entry| entry.album.clone())
            .unwrap_or_default();

        let _ = playback::update_mpris_metadata(
            app::state(),
            playback::MprisMetadata {
                track_id: (*self.track_id()).max(0) as u64,
                title: self.title().to_string(),
                artist: self.artist().to_string(),
                album,
                art_url: art_url(&self.cover().to_string()),
                duration_secs: *self.duration_secs() as f64,
                url: String::new(),
                quality_text: self.quality().to_string(),
                album_artist: None,
                track_number: None,
                disc_number: None,
                content_created: None,
                user_rating: None,
            },
        );
    }

/// Keep playing past the end of the queue from the last track's radio,
    /// the way TIDAL's own autoplay does. Tracks already in the history are
    /// skipped so a short radio does not loop back immediately.
    fn start_autoplay_radio(self: Pin<&mut Self>) {
        if !utility::get_autoplay(app::state()) {
            return;
        }
        let (mix_id, heard) = {
            let queue = self.rust().queue.lock().unwrap();
            let Some(current) = queue.current() else {
                return;
            };
            if current.track_mix.is_empty() {
                return;
            }
            let mut heard: HashSet<i64> = queue.history().iter().map(|e| e.id).collect();
            heard.insert(current.id);
            (current.track_mix.clone(), heard)
        };

        let allow_explicit = utility::get_allow_explicit(app::state());
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let Ok(mix) = pages::get_mix_items(app::state(), mix_id.clone()).await else {
                return;
            };
            let entries: Vec<Entry> = mix
                .tracks
                .iter()
                .filter(|t| !heard.contains(&(t.id as i64)))
                .filter(|t| allow_explicit || !t.explicit.unwrap_or(false))
                .filter_map(|t| entry_from_json(&crate::rows::track_unindexed(t)))
                .collect();
            if entries.is_empty() {
                return;
            }

            let _ = qt.queue(move |mut obj| {
                let first = {
                    let rust = obj.as_mut().rust_mut();
                    let mut queue = rust.queue.lock().unwrap();
                    queue.set_context(entries, 0, format!("radio:{mix_id}"));
                    queue.current().cloned()
                };
                if let Some(entry) = first {
                    obj.as_mut().set_source_label(QString::from("Radio"));
                    obj.start(entry);
                }
            });
        });
    }

    /// Begin playing an entry that the queue has already selected.
    fn start(mut self: Pin<&mut Self>, entry: Entry) {
        let title = QString::from(&entry.title);
        let artist = QString::from(&entry.artist);
        let cover = QString::from(&entry.cover);
        self.as_mut().play(entry.id, &title, &artist, entry.duration, &cover);
        // `play` clears the ids for the ad-hoc case; a queue entry has them.
        self.as_mut().set_artist_id(entry.artist_id);
        self.as_mut().set_album_id(entry.album_id);
        self.publish_queue();
    }
}

impl qobject::PlayerController {
    pub fn play_context(
        self: Pin<&mut Self>,
        tracks_json: &QString,
        index: i32,
        source: &QString,
    ) {
        let entries = entries_from_json(&tracks_json.to_string());
        if entries.is_empty() {
            return;
        }
        let start = {
            let mut queue = self.rust().queue.lock().unwrap();
            queue.set_context(entries, index.max(0) as usize, source.to_string());
            queue.current().cloned()
        };
        if let Some(entry) = start {
            self.start(entry);
        }
    }

    pub fn next(self: Pin<&mut Self>) {
        let entry = self.rust().queue.lock().unwrap().advance(false);
        match entry {
            Some(entry) => self.start(entry),
            None => self.stop(),
        }
    }

    pub fn previous(mut self: Pin<&mut Self>) {
        // Restart the track first, like every other player, and only step back
        // when already near the beginning.
        if *self.position_secs() > 3.0 {
            self.as_mut().seek(0.0);
            return;
        }
        let entry = self.rust().queue.lock().unwrap().previous();
        if let Some(entry) = entry {
            self.start(entry);
        }
    }

    pub fn play_next(mut self: Pin<&mut Self>, track_json: &QString) {
        if let Some(entry) = serde_json::from_str(&track_json.to_string())
            .ok()
            .as_ref()
            .and_then(entry_from_json)
        {
            self.as_mut().rust_mut().queue.lock().unwrap().play_next(entry);
            self.as_mut().publish_queue();
            self.on_queue_changed();
        }
    }

    pub fn enqueue(mut self: Pin<&mut Self>, track_json: &QString) {
        if let Some(entry) = serde_json::from_str(&track_json.to_string())
            .ok()
            .as_ref()
            .and_then(entry_from_json)
        {
            self.as_mut().rust_mut().queue.lock().unwrap().enqueue(entry);
            self.as_mut().publish_queue();
            self.on_queue_changed();
        }
    }

    pub fn extend_context(mut self: Pin<&mut Self>, tracks_json: &QString, source: &QString) {
        let entries = entries_from_json(&tracks_json.to_string());
        if entries.is_empty() {
            return;
        }
        let source = source.to_string();
        let added = {
            let queue = &self.rust().queue;
            let mut queue = queue.lock().unwrap();
            if queue.source() != source {
                return;
            }
            queue.extend_context(entries)
        };
        if added > 0 {
            self.on_queue_changed();
        }
    }

    pub fn jump_to(self: Pin<&mut Self>, index: i32, manual: bool) {
        if index < 0 {
            return;
        }
        let entry = self
            .rust()
            .queue
            .lock()
            .unwrap()
            .jump(index as usize, manual);
        if let Some(entry) = entry {
            self.start(entry);
        }
    }

    pub fn remove_queued(mut self: Pin<&mut Self>, index: i32) {
        if index < 0 {
            return;
        }
        self.as_mut()
            .rust_mut()
            .queue
            .lock()
            .unwrap()
            .remove_manual(index as usize);
        self.as_mut().publish_queue();
        self.on_queue_changed();
    }

    pub fn clear_queue(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().queue.lock().unwrap().clear_manual();
        self.as_mut().publish_queue();
        self.on_queue_changed();
    }

    pub fn toggle_shuffle(mut self: Pin<&mut Self>) {
        let on = !*self.shuffle();
        self.as_mut().rust_mut().queue.lock().unwrap().set_shuffle(on);
        self.as_mut().set_shuffle(on);
        push_shuffle(on);
        self.as_mut().publish_queue();
        self.on_queue_changed();
    }

    pub fn toggle_repeat(mut self: Pin<&mut Self>) {
        let repeat = self.as_mut().rust_mut().queue.lock().unwrap().toggle_repeat();
        self.as_mut().set_repeat(repeat.as_i32());
        push_loop_status(repeat);
        self.on_queue_changed();
    }

    pub fn toggle_mute(mut self: Pin<&mut Self>) {
        let current = *self.volume();
        let restored = self.rust().volume_before_mute;
        let level = if current > 0.0 { 0.0 } else { restored.max(0.05) };
        if current > 0.0 {
            self.as_mut().rust_mut().volume_before_mute = current;
        }
        self.as_mut().set_volume(level);
        self.set_output_volume(level);
    }
}

impl qobject::PlayerController {
    /// Set `playing` and the copy the position poll reads off the Qt thread.
    /// Every transition goes through here; writing the property directly
    /// would leave the poll ticking against a stale answer.
    fn set_playback_active(self: Pin<&mut Self>, on: bool) {
        self.rust().playback_active.store(on, Ordering::Relaxed);
        self.set_playing(on);
    }

    /// Called after anything that can change what plays next: mark the
    /// snapshot for its next debounced save and re-arm the gapless preload.
    fn on_queue_changed(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().queue_dirty = true;
        self.rearm_gapless();
    }

    /// Arm whatever `Queue::gapless_next` reports for the track that is
    /// actually playing, or clear the slot when there is nothing. Skipped when
    /// the queue's `current` does not match `track_id` — an ad-hoc `play()`
    /// outside any queue context has nothing of its own worth prefetching.
    fn rearm_gapless(mut self: Pin<&mut Self>) {
        let now_playing = *self.track_id();
        let next = {
            let queue = self.rust().queue.lock().unwrap();
            if queue.current().map(|e| e.id) != Some(now_playing) {
                return;
            }
            queue.gapless_next().cloned()
        };
        match next {
            Some(entry) => {
                self.as_mut().rust_mut().next_arm_seq += 1;
                let qid = format!("gapless-{}", self.rust().next_arm_seq);
                self.as_mut().rust_mut().armed_qid = qid.clone();
                klang_core::runtime::spawn(async move {
                    let _ = playback::set_next_track(app::state(), entry.id as u64, qid, true).await;
                });
            }
            None => {
                self.as_mut().rust_mut().armed_qid.clear();
                let _ = playback::clear_next_track(app::state());
            }
        }
    }

    /// The pipeline crossed a gapless boundary by itself — an armed next track
    /// took over without a `track-finished`. Catch the queue and display up to
    /// match, without re-issuing `play()` on an already-playing track.
    fn on_gapless_advanced(mut self: Pin<&mut Self>, qid: Option<String>) {
        let armed = self.rust().armed_qid.clone();
        if armed.is_empty() || qid.as_deref() != Some(armed.as_str()) {
            return; // stale advance from a slot already replaced by a re-arm
        }
        let Some(entry) = self.as_mut().rust_mut().queue.lock().unwrap().advance(true) else {
            return;
        };
        self.as_mut().set_title(QString::from(&entry.title));
        self.as_mut().set_artist(QString::from(&entry.artist));
        self.as_mut().set_cover(QString::from(&entry.cover));
        self.as_mut().set_artist_id(entry.artist_id);
        self.as_mut().set_album_id(entry.album_id);
        self.as_mut().set_duration_secs(entry.duration);
        self.as_mut().set_track_id(entry.id);
        self.as_mut().set_position_secs(0.0);
        self.as_mut().set_playback_active(true);
        self.publish_metadata();
        push_playback_status(true, 0.0);
        self.as_mut().publish_queue();
        self.on_queue_changed();
    }

    /// Write the queue and current position, but only if something changed
    /// since the last flush — the position tick marks this dirty every 500 ms
    /// while playing, so writing on every call would defeat the debounce.
    ///
    /// Runs on the Qt thread, so only the snapshot clone happens here: both
    /// the serialisation (~120 KB for a long queue) and
    /// `save_playback_queue`'s synchronous `fs::write` are handed off, or the
    /// GUI would stall on disk every five seconds.
    fn flush_queue_if_dirty(mut self: Pin<&mut Self>) {
        if !self.rust().queue_dirty {
            return;
        }
        self.as_mut().rust_mut().queue_dirty = false;
        let snapshot = QueueSnapshot {
            queue: self.rust().queue.lock().unwrap().clone(),
            position_secs: *self.position_secs(),
        };
        klang_core::runtime::spawn(async move {
            let Ok(json) = serde_json::to_string(&snapshot) else {
                return;
            };
            if let Err(e) = playback::save_playback_queue(app::state(), json) {
                log::warn!("[player] could not save the queue snapshot: {e}");
            }
        });
    }

    /// Bring back the queue and now-playing display from the last session.
    /// The pipeline is left untouched — `toggle`'s cold-start path loads it on
    /// the first press of play, so the app comes back paused, not playing.
    fn restore_queue(mut self: Pin<&mut Self>) {
        let Ok(Some(json)) = playback::load_playback_queue(app::state()) else {
            return;
        };
        let Ok(snapshot) = serde_json::from_str::<QueueSnapshot>(&json) else {
            return;
        };
        let repeat = snapshot.queue.repeat();
        let shuffled = snapshot.queue.is_shuffled();
        let Some(entry) = snapshot.queue.current().cloned() else {
            return;
        };
        *self.as_mut().rust_mut().queue.lock().unwrap() = snapshot.queue;

        self.as_mut().set_title(QString::from(&entry.title));
        self.as_mut().set_artist(QString::from(&entry.artist));
        self.as_mut().set_cover(QString::from(&entry.cover));
        self.as_mut().set_artist_id(entry.artist_id);
        self.as_mut().set_album_id(entry.album_id);
        self.as_mut().set_duration_secs(entry.duration);
        self.as_mut().set_track_id(entry.id);
        self.as_mut().set_position_secs(snapshot.position_secs);
        self.as_mut().set_shuffle(shuffled);
        self.as_mut().set_repeat(repeat.as_i32());
        self.as_mut().publish_queue();
        self.publish_metadata();
        push_playback_status(false, snapshot.position_secs as f64);
        push_shuffle(shuffled);
        push_loop_status(repeat);
    }
}
