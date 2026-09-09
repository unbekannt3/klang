//! A mix: TIDAL's generated playlists, reached from the home carousels.

use crate::bridge::RequestSeq;
use crate::core as app;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use klang_core::api::pages;
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
        #[qproperty(QString, title)]
        #[qproperty(QString, subtitle)]
        #[qproperty(QString, image)]
        #[qproperty(QString, tracks_json)]
        #[qproperty(i32, total)]
        type MixController = super::MixControllerRust;

        #[qinvokable]
        fn load(self: Pin<&mut MixController>, mix_id: &QString);
    }

    impl cxx_qt::Threading for MixController {}
}

pub struct MixControllerRust {
    loading: bool,
    error: QString,
    title: QString,
    subtitle: QString,
    image: QString,
    tracks_json: QString,
    total: i32,
    /// The controller is a QML singleton but `load` runs per navigation, so
    /// mix A landing after mix B would otherwise show A's tracks under B.
    requests: RequestSeq,
}

impl Default for MixControllerRust {
    fn default() -> Self {
        Self {
            loading: false,
            error: QString::default(),
            title: QString::default(),
            subtitle: QString::default(),
            image: QString::default(),
            tracks_json: QString::from("[]"),
            total: 0,
            requests: RequestSeq::default(),
        }
    }
}

impl qobject::MixController {
    pub fn load(mut self: Pin<&mut Self>, mix_id: &QString) {
        let mix_id = mix_id.to_string();
        if mix_id.is_empty() {
            return;
        }
        let token = self.as_mut().rust_mut().requests.start();
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let result = pages::get_mix_items(app::state(), mix_id).await;
            let _ = qt.queue(move |mut obj| {
                if !obj.rust().requests.is_current(token) {
                    return;
                }
                obj.as_mut().set_loading(false);
                match result {
                    Ok(mix) => {
                        let rows: Vec<_> = mix
                            .tracks
                            .iter()
                            .enumerate()
                            .map(|(i, t)| crate::rows::track(i, t))
                            .collect();
                        let json = serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into());
                        obj.as_mut().set_total(rows.len() as i32);
                        obj.as_mut()
                            .set_title(QString::from(&mix.title.unwrap_or_default()));
                        obj.as_mut()
                            .set_subtitle(QString::from(&mix.subtitle.unwrap_or_default()));
                        obj.as_mut()
                            .set_image(QString::from(&mix.image.unwrap_or_default()));
                        obj.as_mut().set_tracks_json(QString::from(&json));
                    }
                    Err(e) => {
                        // Clear the header too — leaving the previous mix's
                        // title and cover above an empty list reads as if
                        // that mix had no tracks.
                        obj.as_mut().set_title(QString::default());
                        obj.as_mut().set_subtitle(QString::default());
                        obj.as_mut().set_image(QString::default());
                        obj.as_mut().set_total(0);
                        obj.as_mut().set_tracks_json(QString::from("[]"));
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }
            });
        });
    }
}
