//! The user's library. For now: loved tracks.
//!
//! The list crosses into QML as a JSON string that `JSON.parse` turns into a
//! plain JS array, which `ListView` accepts as a model. That is the walking
//! skeleton's shortcut — a real `QAbstractListModel` with roles and paging is
//! phase-2 work, and is what virtualised scrolling over thousands of rows
//! needs.

use crate::core as app;
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use klang_core::api::library;
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
        #[qproperty(QString, tracks_json)]
        #[qproperty(QString, error)]
        #[qproperty(i32, total)]
        type LibraryController = super::LibraryControllerRust;

        /// Load the first page of loved tracks for the signed-in user.
        #[qinvokable]
        fn load_favorites(self: Pin<&mut LibraryController>, user_id: i64, limit: i32);
    }

    impl cxx_qt::Threading for LibraryController {}
}

#[derive(Default)]
pub struct LibraryControllerRust {
    loading: bool,
    tracks_json: QString,
    error: QString,
    total: i32,
}

/// Flatten a TIDAL track into what the list row needs. Artist comes from
/// `artist`, falling back to the first entry of `artists` — endpoints differ in
/// which of the two they populate.
fn row(track: &klang_core::tidal_api::TidalTrack) -> serde_json::Value {
    let artist = track
        .artist
        .as_ref()
        .map(|a| a.name.clone())
        .or_else(|| {
            track
                .artists
                .as_ref()
                .and_then(|list| list.first().map(|a| a.name.clone()))
        })
        .unwrap_or_default();

    serde_json::json!({
        "id": track.id,
        "title": track.title,
        "artist": artist,
        "album": track.album.as_ref().map(|a| a.title.clone()).unwrap_or_default(),
        "duration": track.duration,
        "quality": track.audio_quality.clone().unwrap_or_default(),
    })
}

impl qobject::LibraryController {
    pub fn load_favorites(mut self: Pin<&mut Self>, user_id: i64, limit: i32) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let result = library::get_favorite_tracks(
                app::state(),
                app::handle(),
                user_id as u64,
                0,
                limit.max(1) as u32,
                "DATE".to_string(),
                "DESC".to_string(),
            )
            .await;

            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_loading(false);
                match result {
                    Ok(page) => {
                        let rows: Vec<_> = page.items.iter().map(row).collect();
                        let json = serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into());
                        obj.as_mut().set_total(page.total_number_of_items as i32);
                        obj.as_mut().set_tracks_json(QString::from(&json));
                    }
                    Err(e) => {
                        obj.as_mut().set_tracks_json(QString::from("[]"));
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }
            });
        });
    }
}
