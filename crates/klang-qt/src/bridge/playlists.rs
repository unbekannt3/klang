//! The user's playlists and folders.
//!
//! Three views cross into QML as JSON strings the same way `library.rs` does
//! for loved tracks: `playlists_json` is the sidebar tree (every playlist and
//! folder, flattened, each entry carrying a `kind` and a `parent` id so QML
//! can rebuild the hierarchy — mirrors `normalizeFolderItem` in the TS
//! reference client); `playlist_json`/`tracks_json` are the header and track
//! list of whichever playlist is currently open.

use crate::core as app;
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use klang_core::api::{library, metadata};
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
        #[qproperty(QString, playlists_json)]
        #[qproperty(QString, playlist_json)]
        #[qproperty(QString, tracks_json)]
        type PlaylistsController = super::PlaylistsControllerRust;

        /// Load the sidebar tree: every playlist and folder the signed-in
        /// user has, flattened.
        #[qinvokable]
        fn load_all(self: Pin<&mut PlaylistsController>, user_id: i64);

        /// Load one playlist's header and its tracks.
        #[qinvokable]
        fn load_playlist(self: Pin<&mut PlaylistsController>, uuid: &QString);

        /// Create a new unlisted playlist, then refresh the sidebar tree.
        #[qinvokable]
        fn create(self: Pin<&mut PlaylistsController>, title: &QString, description: &QString);

        /// Remove the track at `index` from playlist `uuid`, then refresh its
        /// header and track list.
        #[qinvokable]
        fn remove_track(self: Pin<&mut PlaylistsController>, uuid: &QString, index: i32);
    }

    impl cxx_qt::Threading for PlaylistsController {}
}

#[derive(Default)]
pub struct PlaylistsControllerRust {
    loading: bool,
    error: QString,
    playlists_json: QString,
    playlist_json: QString,
    tracks_json: QString,
}

/// Flatten a TIDAL track into what a playlist row needs, plus its position —
/// `remove_track_from_playlist` addresses tracks by index, not id. Otherwise
/// the same shape as `library::row`, which is private to that module.
/// Build the currently-open playlist's header from the raw
/// `get_playlist_details` response — TIDAL's `/playlists/{uuid}` shape
/// (camelCase, same fields as `TidalPlaylistRaw`), returned unparsed because
/// that endpoint isn't modelled as a typed struct in `klang-core`.
fn playlist_header(uuid: &str, raw: &serde_json::Value) -> serde_json::Value {
    let image = raw
        .get("squareImage")
        .and_then(|v| v.as_str())
        .or_else(|| raw.get("image").and_then(|v| v.as_str()))
        .unwrap_or_default();
    let owner = raw
        .get("creator")
        .and_then(|c| c.get("name"))
        .and_then(|v| v.as_str())
        .unwrap_or_default();

    serde_json::json!({
        "uuid": raw.get("uuid").and_then(|v| v.as_str()).unwrap_or(uuid),
        "title": raw.get("title").and_then(|v| v.as_str()).unwrap_or_default(),
        "description": raw.get("description").and_then(|v| v.as_str()).unwrap_or_default(),
        "owner": owner,
        "trackCount": raw.get("numberOfTracks").and_then(|v| v.as_u64()).unwrap_or(0),
        "duration": raw.get("duration").and_then(|v| v.as_u64()).unwrap_or(0),
        "image": image,
        "public": raw.get("publicPlaylist").and_then(|v| v.as_bool()).unwrap_or(false),
    })
}

/// Normalise one item from `get_all_flattened_playlists` into a sidebar row.
/// Mirrors `normalizeFolderItem` in the TS reference client: a `FOLDER` item
/// carries `name`/`parent` at the top level; a `PLAYLIST` item carries the
/// playlist header fields nested under `data`.
fn folder_item(item: &serde_json::Value) -> serde_json::Value {
    let parent = item
        .get("parent")
        .and_then(|v| v.as_str())
        .unwrap_or_default();
    let data = item.get("data").cloned().unwrap_or(serde_json::Value::Null);

    if item.get("itemType").and_then(|v| v.as_str()) == Some("FOLDER") {
        let id = item
            .get("trn")
            .and_then(|v| v.as_str())
            .map(|trn| trn.trim_start_matches("trn:folder:").to_string())
            .unwrap_or_default();
        let name = item
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or_default();
        let track_count = data
            .get("totalNumberOfItems")
            .and_then(|v| v.as_u64())
            .unwrap_or(0);

        serde_json::json!({
            "kind": "folder",
            "id": id,
            "name": name,
            "parent": parent,
            "trackCount": track_count,
        })
    } else {
        let image = data
            .get("squareImage")
            .and_then(|v| v.as_str())
            .or_else(|| data.get("image").and_then(|v| v.as_str()))
            .unwrap_or_default();
        let owner = data
            .get("creator")
            .and_then(|c| c.get("name"))
            .and_then(|v| v.as_str())
            .unwrap_or_default();

        serde_json::json!({
            "kind": "playlist",
            "id": data.get("uuid").and_then(|v| v.as_str()).unwrap_or_default(),
            "title": data.get("title").and_then(|v| v.as_str()).unwrap_or_default(),
            "description": data.get("description").and_then(|v| v.as_str()).unwrap_or_default(),
            "owner": owner,
            "trackCount": data.get("numberOfTracks").and_then(|v| v.as_u64()).unwrap_or(0),
            "duration": data.get("duration").and_then(|v| v.as_u64()).unwrap_or(0),
            "image": image,
            "public": data.get("publicPlaylist").and_then(|v| v.as_bool()).unwrap_or(false),
            "parent": parent,
        })
    }
}

impl qobject::PlaylistsController {
    pub fn load_all(mut self: Pin<&mut Self>, user_id: i64) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let qt = self.qt_thread();

        // The flattened-folders endpoint is scoped to the signed-in user via
        // the session's own tokens rather than a request parameter; `user_id`
        // is accepted for parity with the other loaders (`load_favorites`).
        log::debug!("[PlaylistsController::load_all]: user_id={}", user_id);

        klang_core::runtime::spawn(async move {
            let result = library::get_all_flattened_playlists(app::state()).await;

            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_loading(false);
                match result {
                    Ok(items) => {
                        let rows: Vec<_> = items.iter().map(folder_item).collect();
                        let json = serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into());
                        obj.as_mut().set_playlists_json(QString::from(&json));
                    }
                    Err(e) => {
                        obj.as_mut().set_playlists_json(QString::from("[]"));
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }
            });
        });
    }

    pub fn load_playlist(mut self: Pin<&mut Self>, uuid: &QString) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let qt = self.qt_thread();
        let playlist_id = uuid.to_string();

        klang_core::runtime::spawn(async move {
            let (details, tracks) = tokio::join!(
                metadata::get_playlist_details(app::state(), playlist_id.clone()),
                library::get_playlist_tracks(app::state(), app::handle(), playlist_id.clone()),
            );

            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_loading(false);

                match details {
                    Ok(raw) => {
                        let header = playlist_header(&playlist_id, &raw);
                        let json = serde_json::to_string(&header).unwrap_or_else(|_| "{}".into());
                        obj.as_mut().set_playlist_json(QString::from(&json));
                    }
                    Err(e) => {
                        obj.as_mut().set_playlist_json(QString::from("{}"));
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }

                match tracks {
                    Ok(list) => {
                        let rows: Vec<_> =
                            list.iter().enumerate().map(|(i, t)| crate::rows::track(i, t)).collect();
                        let json = serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into());
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

    pub fn create(mut self: Pin<&mut Self>, title: &QString, description: &QString) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let qt = self.qt_thread();
        let title = title.to_string();
        let description = description.to_string();

        klang_core::runtime::spawn(async move {
            let created = library::create_playlist(
                app::state(),
                title,
                description,
                "UNLISTED".to_string(),
            )
            .await;

            if let Err(e) = created {
                let _ = qt.queue(move |mut obj| {
                    obj.as_mut().set_loading(false);
                    obj.as_mut().set_error(QString::from(&e.to_string()));
                });
                return;
            }

            // Refresh the sidebar tree so the new playlist shows up.
            let refreshed = library::get_all_flattened_playlists(app::state()).await;

            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_loading(false);
                match refreshed {
                    Ok(items) => {
                        let rows: Vec<_> = items.iter().map(folder_item).collect();
                        let json = serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into());
                        obj.as_mut().set_playlists_json(QString::from(&json));
                    }
                    Err(e) => {
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }
            });
        });
    }

    pub fn remove_track(mut self: Pin<&mut Self>, uuid: &QString, index: i32) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let qt = self.qt_thread();
        let playlist_id = uuid.to_string();
        let idx = index.max(0) as u32;

        klang_core::runtime::spawn(async move {
            let removed =
                library::remove_track_from_playlist(app::state(), playlist_id.clone(), idx).await;

            if let Err(e) = removed {
                let _ = qt.queue(move |mut obj| {
                    obj.as_mut().set_loading(false);
                    obj.as_mut().set_error(QString::from(&e.to_string()));
                });
                return;
            }

            // The track count/duration changed — refresh header and list.
            let (details, tracks) = tokio::join!(
                metadata::get_playlist_details(app::state(), playlist_id.clone()),
                library::get_playlist_tracks(app::state(), app::handle(), playlist_id.clone()),
            );

            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_loading(false);

                match details {
                    Ok(raw) => {
                        let header = playlist_header(&playlist_id, &raw);
                        let json = serde_json::to_string(&header).unwrap_or_else(|_| "{}".into());
                        obj.as_mut().set_playlist_json(QString::from(&json));
                    }
                    Err(e) => {
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }

                match tracks {
                    Ok(list) => {
                        let rows: Vec<_> =
                            list.iter().enumerate().map(|(i, t)| crate::rows::track(i, t)).collect();
                        let json = serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into());
                        obj.as_mut().set_tracks_json(QString::from(&json));
                    }
                    Err(e) => {
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }
            });
        });
    }
}
