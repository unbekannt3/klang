//! Music video playback support: stream/metadata resolution and per-video
//! favourite state for the takeover video player.
//!
//! Actual playback happens in QML via QtMultimedia (`MediaPlayer` +
//! `VideoOutput`, see `VideoPlayerView.qml`) — this controller only resolves
//! what to play. It holds no reference to the audio pipeline (`player.rs` is
//! off limits here): starting a video must stop the audio player first, so
//! `load_video` emits `pause_audio_requested` and leaves the actual pause to
//! whoever connects that signal (see the report for the Main.qml wiring).

use crate::core as app;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use klang_core::api::{library, playback};
use klang_core::tidal_api::TidalVideo;
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
        #[qproperty(i64, video_id)]
        #[qproperty(QString, title)]
        #[qproperty(QString, artist)]
        #[qproperty(QString, cover)]
        #[qproperty(bool, explicit)]
        #[qproperty(f32, duration_secs)]
        #[qproperty(QString, stream_url)]
        /// What TIDAL actually served, not necessarily what was requested.
        #[qproperty(QString, quality)]
        #[qproperty(bool, is_favorite)]
        type VideoController = super::VideoControllerRust;

        /// Resolve a video's metadata, favourite state and HLS stream, then
        /// show it. Emits `pause_audio_requested` synchronously, before any of
        /// that resolves — the takeover should never compete with the audio
        /// player for the output device.
        #[qinvokable]
        fn load_video(
            self: Pin<&mut VideoController>,
            video_id: i64,
            quality: &QString,
            user_id: i64,
        );

        /// Re-resolve the stream at a different quality tier, keeping the
        /// rest of the metadata as-is. Named `select_quality`, not
        /// `set_quality` — that name is already the `quality` property's own
        /// generated setter.
        #[qinvokable]
        fn select_quality(self: Pin<&mut VideoController>, quality: &QString);

        /// Add when absent, remove when present.
        #[qinvokable]
        fn toggle_favorite(self: Pin<&mut VideoController>);

        /// Close the takeover: clears every property back to its default so
        /// a `video_id !== 0` visibility binding drops the overlay.
        #[qinvokable]
        fn close(self: Pin<&mut VideoController>);

        /// The audio pipeline is off limits to this controller (see module
        /// docs) — pausing it is left to whoever connects this signal.
        #[qsignal]
        fn pause_audio_requested(self: Pin<&mut VideoController>);
    }

    impl cxx_qt::Threading for VideoController {}
}

#[derive(Default)]
pub struct VideoControllerRust {
    loading: bool,
    error: QString,
    video_id: i64,
    title: QString,
    artist: QString,
    cover: QString,
    explicit: bool,
    duration_secs: f32,
    stream_url: QString,
    quality: QString,
    is_favorite: bool,
    /// Remembered so `toggle_favorite` doesn't need the caller to pass it
    /// again — same convention as `FavoritesControllerRust::user_id`.
    user_id: i64,
    /// Bumped by every request and by `close`; a queued response is applied
    /// only if it still matches, so a superseded `load_video`/`select_quality`
    /// or a `close` mid-flight can never clobber newer state.
    request_seq: u64,
}

/// Same `artist`/`artists` fallback chain as `library.rs`'s `video_card_row`
/// (private there, so duplicated here rather than reached across modules).
fn video_artist_name(video: &TidalVideo) -> String {
    video
        .artist
        .as_ref()
        .map(|a| a.name.clone())
        .or_else(|| video.artists.as_ref().and_then(|list| list.first().map(|a| a.name.clone())))
        .unwrap_or_default()
}

impl qobject::VideoController {
    pub fn load_video(mut self: Pin<&mut Self>, video_id: i64, quality: &QString, user_id: i64) {
        self.as_mut().pause_audio_requested();

        let seq = self.rust().request_seq.wrapping_add(1);
        self.as_mut().rust_mut().request_seq = seq;
        self.as_mut().rust_mut().user_id = user_id;

        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        self.as_mut().set_video_id(video_id);
        self.as_mut().set_title(QString::from(""));
        self.as_mut().set_artist(QString::from(""));
        self.as_mut().set_cover(QString::from(""));
        self.as_mut().set_explicit(false);
        self.as_mut().set_duration_secs(0.0);
        self.as_mut().set_stream_url(QString::from(""));
        // Optimistic label until the served tier is known — mirrors the
        // requested tier, same as sone's quality dropdown did before resolve.
        self.as_mut().set_quality(quality.clone());
        self.as_mut().set_is_favorite(false);

        let qt = self.qt_thread();
        let id = video_id.max(0) as u64;
        let user = user_id.max(0) as u64;
        let quality_req = quality.to_string();

        klang_core::runtime::spawn(async move {
            let (stream_result, meta_result, fav_result) = tokio::join!(
                playback::get_video_stream_info(app::state(), id, Some(quality_req)),
                playback::get_video_metadata(app::state(), id),
                library::get_favorite_video_ids(app::state(), user),
            );

            let _ = qt.queue(move |mut obj| {
                if obj.rust().request_seq != seq {
                    return; // superseded by a newer load_video/select_quality/close
                }
                obj.as_mut().set_loading(false);
                let mut errors = Vec::new();

                match meta_result {
                    Ok(video) => {
                        obj.as_mut().set_title(QString::from(&video.title));
                        obj.as_mut().set_artist(QString::from(&video_artist_name(&video)));
                        obj.as_mut()
                            .set_cover(QString::from(&video.image_id.clone().unwrap_or_default()));
                        obj.as_mut().set_explicit(video.explicit.unwrap_or(false));
                        obj.as_mut()
                            .set_duration_secs(video.duration.unwrap_or(0) as f32);
                    }
                    Err(e) => errors.push(e.to_string()),
                }

                match stream_result {
                    Ok(stream) => {
                        obj.as_mut().set_stream_url(QString::from(&stream.url));
                        obj.as_mut().set_quality(QString::from(&stream.video_quality));
                    }
                    Err(e) => errors.push(e.to_string()),
                }

                match fav_result {
                    // TIDAL has no single-id favourite-video check (unlike
                    // tracks/albums), so this fetches the whole id list.
                    Ok(ids) => obj.as_mut().set_is_favorite(ids.contains(&id)),
                    Err(e) => log::warn!("[load_video] favourite state: {e}"),
                }

                if !errors.is_empty() {
                    obj.as_mut().set_error(QString::from(&errors.join("; ")));
                }
            });
        });
    }

    pub fn select_quality(mut self: Pin<&mut Self>, quality: &QString) {
        let video_id = self.rust().video_id;
        if video_id == 0 {
            return;
        }
        let seq = self.rust().request_seq.wrapping_add(1);
        self.as_mut().rust_mut().request_seq = seq;
        self.as_mut().set_error(QString::from(""));

        let qt = self.qt_thread();
        let id = video_id as u64;
        let quality_req = quality.to_string();

        klang_core::runtime::spawn(async move {
            let result = playback::get_video_stream_info(app::state(), id, Some(quality_req)).await;
            let _ = qt.queue(move |mut obj| {
                if obj.rust().request_seq != seq {
                    return;
                }
                match result {
                    Ok(stream) => {
                        obj.as_mut().set_stream_url(QString::from(&stream.url));
                        obj.as_mut().set_quality(QString::from(&stream.video_quality));
                    }
                    Err(e) => obj.as_mut().set_error(QString::from(&e.to_string())),
                }
            });
        });
    }

    pub fn toggle_favorite(mut self: Pin<&mut Self>) {
        let video_id = self.rust().video_id;
        let user_id = self.rust().user_id;
        if video_id == 0 || user_id == 0 {
            return;
        }

        let adding = !*self.is_favorite();
        self.as_mut().set_is_favorite(adding);
        let qt = self.qt_thread();
        let vid = video_id as u64;
        let user = user_id as u64;

        klang_core::runtime::spawn(async move {
            let result = if adding {
                library::add_favorite_video(app::state(), user, vid).await
            } else {
                library::remove_favorite_video(app::state(), user, vid).await
            };
            if let Err(e) = result {
                let msg = e.to_string();
                let _ = qt.queue(move |mut obj| {
                    // Roll back only if still showing the same video.
                    if obj.rust().video_id == vid as i64 {
                        obj.as_mut().set_is_favorite(!adding);
                    }
                    obj.as_mut().set_error(QString::from(&msg));
                });
            }
        });
    }

    pub fn close(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().request_seq = self.rust().request_seq.wrapping_add(1);
        self.as_mut().set_loading(false);
        self.as_mut().set_error(QString::from(""));
        self.as_mut().set_video_id(0);
        self.as_mut().set_title(QString::from(""));
        self.as_mut().set_artist(QString::from(""));
        self.as_mut().set_cover(QString::from(""));
        self.as_mut().set_explicit(false);
        self.as_mut().set_duration_secs(0.0);
        self.as_mut().set_stream_url(QString::from(""));
        self.as_mut().set_quality(QString::from(""));
        self.as_mut().set_is_favorite(false);
    }
}
