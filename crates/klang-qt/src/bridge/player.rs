//! Playback control and the now-playing state QML binds to.

use crate::core as app;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use crate::queue::{Entry, Queue};
use klang_core::api::playback;
use std::pin::Pin;
use std::sync::Mutex;

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
        #[qproperty(QString, quality)]
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

        /// Name shown as "playing from"; the source id alone is not readable.
        #[qinvokable]
        fn set_source_name(self: Pin<&mut PlayerController>, name: &QString);

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
    quality: QString,
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
            quality: QString::default(),
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
        self.as_mut().set_duration_secs(duration);
        self.as_mut().set_position_secs(0.0);
        self.as_mut().set_track_id(track_id);
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            // use_track_gain: true — a hand-picked track is not album playback,
            // so track gain is the right normalization reference.
            let result = playback::play_tidal_track(app::state(), track_id as u64, true).await;
            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_busy(false);
                match result {
                    Ok(info) => {
                        obj.as_mut().set_quality(QString::from(&quality_label(&info)));
                        obj.as_mut().set_playing(true);
                    }
                    Err(e) => {
                        obj.as_mut().set_playing(false);
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }
            });
        });
    }

    pub fn toggle(mut self: Pin<&mut Self>) {
        let want_play = !*self.playing();
        self.as_mut().set_playing(want_play);
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
                    obj.as_mut().set_playing(!want_play);
                    obj.as_mut().set_error(QString::from(&msg));
                });
            }
        });
    }

    pub fn stop(mut self: Pin<&mut Self>) {
        self.as_mut().set_playing(false);
        self.as_mut().set_position_secs(0.0);
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

        // Position poll. The pipeline is the source of truth for where we are;
        // 500 ms is the cadence the React UI used.
        let qt = self.qt_thread();
        klang_core::runtime::spawn(async move {
            let mut tick = tokio::time::interval(std::time::Duration::from_millis(500));
            loop {
                tick.tick().await;
                let Ok(pos) = playback::get_playback_position(app::state()) else {
                    continue;
                };
                let _ = qt.queue(move |mut obj| {
                    if *obj.playing() {
                        obj.as_mut().set_position_secs(pos);
                    }
                });
            }
        });

        // Core events. `audio-error` is the one the user must see; the rest of
        // the catalogue lands here as the bridge grows.
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
                                    obj.as_mut().set_playing(false);
                                    obj.as_mut().set_position_secs(0.0);
                                }
                            }
                        });
                    }
                    "audio-error" => {
                        let msg = event
                            .payload
                            .get("message")
                            .and_then(|v| v.as_str())
                            .unwrap_or("playback failed")
                            .to_string();
                        let _ = qt.queue(move |mut obj| {
                            obj.as_mut().set_playing(false);
                            obj.as_mut().set_error(QString::from(&msg));
                        });
                    }
                    _ => {}
                }
            }
        });
    }
}

/// Parse one row from `rows.rs` into a queue entry.
fn entry_from_json(value: &serde_json::Value) -> Option<Entry> {
    Some(Entry {
        id: value.get("id")?.as_i64()?,
        title: value.get("title").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
        artist: value.get("artist").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
        duration: value.get("duration").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32,
        cover: value.get("cover").and_then(|v| v.as_str()).unwrap_or_default().to_string(),
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
    pub fn set_source_name(mut self: Pin<&mut Self>, name: &QString) {
        self.as_mut().set_source_label(name.clone());
    }

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

    /// Begin playing an entry that the queue has already selected.
    fn start(mut self: Pin<&mut Self>, entry: Entry) {
        let title = QString::from(&entry.title);
        let artist = QString::from(&entry.artist);
        let cover = QString::from(&entry.cover);
        self.as_mut().play(entry.id, &title, &artist, entry.duration, &cover);
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
            self.publish_queue();
        }
    }

    pub fn enqueue(mut self: Pin<&mut Self>, track_json: &QString) {
        if let Some(entry) = serde_json::from_str(&track_json.to_string())
            .ok()
            .as_ref()
            .and_then(entry_from_json)
        {
            self.as_mut().rust_mut().queue.lock().unwrap().enqueue(entry);
            self.publish_queue();
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
        self.publish_queue();
    }

    pub fn clear_queue(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().queue.lock().unwrap().clear_manual();
        self.publish_queue();
    }

    pub fn toggle_shuffle(mut self: Pin<&mut Self>) {
        let on = !*self.shuffle();
        self.as_mut().rust_mut().queue.lock().unwrap().set_shuffle(on);
        self.as_mut().set_shuffle(on);
        self.publish_queue();
    }

    pub fn toggle_repeat(mut self: Pin<&mut Self>) {
        let repeat = self.as_mut().rust_mut().queue.lock().unwrap().toggle_repeat();
        self.as_mut().set_repeat(repeat.as_i32());
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
