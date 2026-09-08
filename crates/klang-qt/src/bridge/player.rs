//! Playback control and the now-playing state QML binds to.

use crate::core as app;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use klang_core::api::playback;
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
        #[qproperty(bool, playing)]
        #[qproperty(bool, busy)]
        #[qproperty(f32, position_secs)]
        #[qproperty(f32, duration_secs)]
        #[qproperty(QString, title)]
        #[qproperty(QString, artist)]
        #[qproperty(QString, quality)]
        #[qproperty(QString, error)]
        #[qproperty(i64, track_id)]
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

        /// Start the position poll and subscribe to core events. Call once.
        #[qinvokable]
        fn attach(self: Pin<&mut PlayerController>);
    }

    impl cxx_qt::Threading for PlayerController {}
}

#[derive(Default)]
pub struct PlayerControllerRust {
    playing: bool,
    busy: bool,
    position_secs: f32,
    duration_secs: f32,
    title: QString,
    artist: QString,
    quality: QString,
    error: QString,
    track_id: i64,
    attached: bool,
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
    ) {
        self.as_mut().set_busy(true);
        self.as_mut().set_error(QString::from(""));
        self.as_mut().set_title(title.clone());
        self.as_mut().set_artist(artist.clone());
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

    pub fn set_output_volume(self: Pin<&mut Self>, level: f32) {
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
                            obj.as_mut().set_playing(false);
                            obj.as_mut().set_position_secs(0.0);
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
