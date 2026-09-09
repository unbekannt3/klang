//! The three panels beside the now-playing cover: lyrics, credits and the
//! track's own radio as "suggested tracks".
//!
//! All three key off one track id and are refetched whenever it changes, so
//! they share a controller rather than three near-identical ones.

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
        /// Plain text, empty when TIDAL has no lyrics for the track.
        #[qproperty(QString, lyrics)]
        /// Timestamped lyrics, in the LRC form TIDAL returns. Empty when the
        /// track only has the plain kind.
        #[qproperty(QString, subtitles)]
        #[qproperty(QString, lyrics_provider)]
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
    lyrics: QString,
    subtitles: QString,
    lyrics_provider: QString,
    credits_json: QString,
    suggested_json: QString,
    /// What the last `load` was for, so repeated property writes for the same
    /// track do not refetch.
    track_id: i64,
}

/// TIDAL nests a track's own radio under `mixes.TRACK_MIX`. `get_track`
/// hands back the raw payload rather than a typed track, so this reads it
/// off the JSON.
fn track_mix_id(track: &serde_json::Value) -> Option<String> {
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
            let mix_id = metadata::get_track(app::state(), id)
                .await
                .ok()
                .and_then(|track| track_mix_id(&track));
            let suggested = match mix_id {
                Some(mix_id) => pages::get_mix_items(app::state(), mix_id).await.ok(),
                None => None,
            };

            let _ = qt.queue(move |mut obj| {
                // A newer track was requested while this was in flight.
                if obj.rust().track_id != track_id {
                    return;
                }
                obj.as_mut().set_loading(false);

                if let Ok(lyrics) = lyrics {
                    obj.as_mut()
                        .set_lyrics(QString::from(&lyrics.lyrics.unwrap_or_default()));
                    obj.as_mut()
                        .set_subtitles(QString::from(&lyrics.subtitles.unwrap_or_default()));
                    obj.as_mut().set_lyrics_provider(QString::from(
                        &lyrics.lyrics_provider.unwrap_or_default(),
                    ));
                }

                if let Ok(credits) = credits {
                    let rows: Vec<_> = credits
                        .iter()
                        .map(|credit| {
                            serde_json::json!({
                                "role": credit.credit_type,
                                "contributors": credit
                                    .contributors
                                    .iter()
                                    .map(|c| c.name.clone())
                                    .collect::<Vec<_>>(),
                            })
                        })
                        .collect();
                    obj.as_mut().set_credits_json(QString::from(
                        &serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into()),
                    ));
                }

                if let Some(mix) = suggested {
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
            });
        });
    }

    fn clear(mut self: Pin<&mut Self>) {
        self.as_mut().set_lyrics(QString::default());
        self.as_mut().set_subtitles(QString::default());
        self.as_mut().set_lyrics_provider(QString::default());
        self.as_mut().set_credits_json(QString::from("[]"));
        self.as_mut().set_suggested_json(QString::from("[]"));
    }
}
