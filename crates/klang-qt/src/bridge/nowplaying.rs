//! The three panels beside the now-playing cover: lyrics, credits and the
//! track's own radio as "suggested tracks".
//!
//! All three key off one track id and are refetched whenever it changes, so
//! they share a controller rather than three near-identical ones.

use crate::bridge::media_row::credit_row;
use crate::core as app;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use klang_core::api::{metadata, pages};
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
        /// Whatever of the three panels failed, joined. Empty when everything
        /// that was asked for came back — a track with no lyrics is a success
        /// with an empty `lyrics`, not an error.
        #[qproperty(QString, error)]
        /// Plain text, empty when TIDAL has no lyrics for the track.
        #[qproperty(QString, lyrics)]
        /// `[{ role, contributors: [name] }]`, same shape as the album page.
        #[qproperty(QString, credits_json)]
        /// Track rows from the track's radio mix.
        #[qproperty(QString, suggested_json)]
        type NowPlayingController = super::NowPlayingControllerRust;

        /// Load all three panels for a track. Passing 0 clears them.
        #[qinvokable]
        fn load(self: Pin<&mut NowPlayingController>, track_id: i64);
    }

    impl cxx_qt::Threading for NowPlayingController {}
}

#[derive(Default)]
pub struct NowPlayingControllerRust {
    loading: bool,
    error: QString,
    lyrics: QString,
    credits_json: QString,
    suggested_json: QString,
    /// What the last `load` was for, so repeated property writes for the same
    /// track do not refetch.
    track_id: i64,
}

/// TIDAL nests a track's own radio under `mixes.TRACK_MIX`. `get_track`
/// hands back the raw payload rather than a typed track, so this reads it
/// off the JSON — `rows.rs` has the same lookup for a typed `TidalTrack`,
/// which is a different enough input not to share one function.
pub(crate) fn track_mix_id(track: &serde_json::Value) -> Option<String> {
    track.get("mixes")?.get("TRACK_MIX")?.as_str().map(str::to_string)
}

impl qobject::NowPlayingController {
    pub fn load(mut self: Pin<&mut Self>, track_id: i64) {
        if track_id == self.rust().track_id {
            return;
        }
        self.as_mut().rust_mut().track_id = track_id;
        self.as_mut().clear();

        if track_id <= 0 {
            return;
        }
        self.as_mut().set_loading(true);

        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let id = track_id as u64;
            let (lyrics, credits) = tokio::join!(
                metadata::get_track_lyrics(app::state(), id),
                metadata::get_track_credits(app::state(), id),
            );
            // The radio id lives on the track payload rather than on
            // anything the player carries, so it takes its own lookup; a
            // track without one simply has no suggestions.
            let track = metadata::get_track(app::state(), id).await;
            let mix_id = track.as_ref().ok().and_then(|t| track_mix_id(t));
            let suggested = match mix_id {
                Some(mix_id) => Some(pages::get_mix_items(app::state(), mix_id).await),
                None => None,
            };

            let _ = qt.queue(move |mut obj| {
                // A newer track was requested while this was in flight.
                if obj.rust().track_id != track_id {
                    return;
                }
                obj.as_mut().set_loading(false);
                let mut errors = Vec::new();

                match lyrics {
                    Ok(lyrics) => obj
                        .as_mut()
                        .set_lyrics(QString::from(&lyrics.lyrics.unwrap_or_default())),
                    Err(e) => {
                        log::warn!("[nowplaying] lyrics for {track_id}: {e}");
                        errors.push(e.to_string());
                    }
                }

                match credits {
                    Ok(credits) => {
                        let rows: Vec<_> = credits.iter().map(credit_row).collect();
                        obj.as_mut().set_credits_json(QString::from(
                            &serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into()),
                        ));
                    }
                    Err(e) => {
                        log::warn!("[nowplaying] credits for {track_id}: {e}");
                        errors.push(e.to_string());
                    }
                }

                if let Err(e) = track {
                    log::warn!("[nowplaying] track lookup for {track_id}: {e}");
                    errors.push(e.to_string());
                }

                match suggested {
                    Some(Ok(mix)) => {
                        let rows: Vec<_> = mix
                            .tracks
                            .iter()
                            .enumerate()
                            .map(|(i, t)| crate::rows::track(i, t))
                            .collect();
                        obj.as_mut().set_suggested_json(QString::from(
                            &serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into()),
                        ));
                    }
                    Some(Err(e)) => {
                        log::warn!("[nowplaying] radio mix for {track_id}: {e}");
                        errors.push(e.to_string());
                    }
                    // No TRACK_MIX on the payload — nothing was asked for.
                    None => {}
                }

                if !errors.is_empty() {
                    obj.as_mut().set_error(QString::from(&errors.join("; ")));
                }
            });
        });
    }

    fn clear(mut self: Pin<&mut Self>) {
        self.as_mut().set_error(QString::default());
        self.as_mut().set_lyrics(QString::default());
        self.as_mut().set_credits_json(QString::from("[]"));
        self.as_mut().set_suggested_json(QString::from("[]"));
    }
}
