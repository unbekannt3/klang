//! The user's playlists and folders.
//!
//! Three views cross into QML as JSON strings the same way `library.rs` does
//! for loved tracks: `playlists_json` is the sidebar tree (every playlist and
//! folder, flattened, each entry carrying a `kind` and a `parent` id so QML
//! can rebuild the hierarchy — mirrors `normalizeFolderItem` in the TS
//! reference client); `playlist_json`/`tracks_json` are the header and track
//! list of whichever playlist is currently open.

use crate::bridge::RequestSeq;
use crate::core as app;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use klang_core::api::{auth, library, metadata};
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

        /// Add one track to a playlist, then refresh the sidebar tree.
        #[qinvokable]
        fn add_track(self: Pin<&mut PlaylistsController>, uuid: &QString, track_id: i64);

        /// Create a playlist and add one track to it, for the picker's
        /// "New playlist" path.
        #[qinvokable]
        fn create_with_track(self: Pin<&mut PlaylistsController>, title: &QString, track_id: i64);

        /// Save a whole list of tracks as a new playlist — the queue, turned
        /// into something that outlives it.
        #[qinvokable]
        fn create_with_tracks(
            self: Pin<&mut PlaylistsController>,
            title: &QString,
            track_ids_json: &QString,
        );

        /// Delete a playlist, then refresh the sidebar tree.
        #[qinvokable]
        fn remove(self: Pin<&mut PlaylistsController>, uuid: &QString);

        /// Change title, description and visibility together — the
        /// PlaylistEditDialog save path. The access type is explicit rather
        /// than read back first, since the dialog always knows it.
        #[qinvokable]
        fn update_metadata(
            self: Pin<&mut PlaylistsController>,
            uuid: &QString,
            title: &QString,
            description: &QString,
            is_public: bool,
        );

        /// Move the track at `from_index` to `to_index` within a playlist,
        /// then refresh its header and track list.
        #[qinvokable]
        fn move_track(
            self: Pin<&mut PlaylistsController>,
            uuid: &QString,
            from_index: i32,
            to_index: i32,
        );

        /// Create a new top-level folder.
        #[qinvokable]
        fn create_folder(self: Pin<&mut PlaylistsController>, name: &QString);

        /// Rename a folder.
        #[qinvokable]
        fn rename_folder(self: Pin<&mut PlaylistsController>, id: &QString, name: &QString);

        /// Delete a folder. TIDAL refuses this while the folder still holds
        /// playlists; the failure surfaces through `error` like any other.
        #[qinvokable]
        fn delete_folder(self: Pin<&mut PlaylistsController>, id: &QString);

        /// Move a playlist into a folder, or to the top level when
        /// `folder_id` is empty.
        #[qinvokable]
        fn move_to_folder(
            self: Pin<&mut PlaylistsController>,
            playlist_uuid: &QString,
            folder_id: &QString,
        );
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

    /// The sidebar tree and the open playlist load independently — one
    /// sequence each, so opening a playlist does not cancel the tree load
    /// still in flight from start-up. Every mutation that refreshes one of
    /// them takes a token too, so a read issued before the write cannot land
    /// after it and show the pre-write state.
    tree_requests: RequestSeq,
    playlist_requests: RequestSeq,
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
            // For the sidebar's own sort and its yours/others filter.
            "ownerId": data.get("creator").and_then(|c| c.get("id")).and_then(|v| v.as_i64()),
            "created": data.get("created").and_then(|v| v.as_str()),
            "updated": data.get("lastUpdated").and_then(|v| v.as_str()),
        })
    }
}

impl qobject::PlaylistsController {
    pub fn load_all(mut self: Pin<&mut Self>, user_id: i64) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let token = self.as_mut().rust_mut().tree_requests.start();
        let qt = self.qt_thread();

        // The flattened-folders endpoint is scoped to the signed-in user via
        // the session's own tokens rather than a request parameter; `user_id`
        // is accepted for parity with the other loaders (`load_favorites`).
        log::debug!("[PlaylistsController::load_all]: user_id={}", user_id);

        klang_core::runtime::spawn(async move {
            let result = library::get_all_flattened_playlists(app::state()).await;

            let _ = qt.queue(move |mut obj| {
                if !obj.rust().tree_requests.is_current(token) {
                    return;
                }
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
        let token = self.as_mut().rust_mut().playlist_requests.start();
        let qt = self.qt_thread();
        let playlist_id = uuid.to_string();

        klang_core::runtime::spawn(async move {
            let (details, tracks) = tokio::join!(
                metadata::get_playlist_details(app::state(), playlist_id.clone()),
                library::get_playlist_tracks(app::state(), app::handle(), playlist_id.clone()),
            );

            let _ = qt.queue(move |mut obj| {
                if !obj.rust().playlist_requests.is_current(token) {
                    return;
                }
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

    pub fn add_track(mut self: Pin<&mut Self>, uuid: &QString, track_id: i64) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let token = self.as_mut().rust_mut().tree_requests.start();
        let qt = self.qt_thread();
        let playlist_id = uuid.to_string();
        let track = track_id.max(0) as u64;

        klang_core::runtime::spawn(async move {
            let added =
                library::add_track_to_playlist(app::state(), playlist_id.clone(), track).await;

            if let Err(e) = added {
                let _ = qt.queue(move |mut obj| {
                    obj.as_mut().set_loading(false);
                    obj.as_mut().set_error(QString::from(&e.to_string()));
                });
                return;
            }

            let refreshed = library::get_all_flattened_playlists(app::state()).await;

            let _ = qt.queue(move |mut obj| {
                if !obj.rust().tree_requests.is_current(token) {
                    return;
                }
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

    pub fn create_with_tracks(
        mut self: Pin<&mut Self>,
        title: &QString,
        track_ids_json: &QString,
    ) {
        let ids: Vec<u64> = serde_json::from_str::<Vec<i64>>(&track_ids_json.to_string())
            .unwrap_or_default()
            .into_iter()
            .filter(|id| *id > 0)
            .map(|id| id as u64)
            .collect();
        if ids.is_empty() {
            return;
        }
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let token = self.as_mut().rust_mut().tree_requests.start();
        let qt = self.qt_thread();
        let title = title.to_string();

        klang_core::runtime::spawn(async move {
            let created = library::create_playlist(
                app::state(),
                title,
                String::new(),
                "UNLISTED".to_string(),
            )
            .await;

            let playlist = match created {
                Ok(p) => p,
                Err(e) => {
                    let _ = qt.queue(move |mut obj| {
                        obj.as_mut().set_loading(false);
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    });
                    return;
                }
            };

            if let Err(e) =
                library::add_tracks_to_playlist(app::state(), playlist.uuid.clone(), ids).await
            {
                let _ = qt.queue(move |mut obj| {
                    obj.as_mut().set_loading(false);
                    obj.as_mut().set_error(QString::from(&e.to_string()));
                });
                return;
            }

            let refreshed = library::get_all_flattened_playlists(app::state()).await;

            let _ = qt.queue(move |mut obj| {
                if !obj.rust().tree_requests.is_current(token) {
                    return;
                }
                obj.as_mut().set_loading(false);
                match refreshed {
                    Ok(items) => {
                        let rows: Vec<_> = items.iter().map(folder_item).collect();
                        let json = serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into());
                        obj.as_mut().set_playlists_json(QString::from(&json));
                    }
                    Err(e) => obj.as_mut().set_error(QString::from(&e.to_string())),
                }
            });
        });
    }

    pub fn create_with_track(mut self: Pin<&mut Self>, title: &QString, track_id: i64) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let token = self.as_mut().rust_mut().tree_requests.start();
        let qt = self.qt_thread();
        let title = title.to_string();
        let track = track_id.max(0) as u64;

        klang_core::runtime::spawn(async move {
            let created = library::create_playlist(
                app::state(),
                title.clone(),
                String::new(),
                "UNLISTED".to_string(),
            )
            .await;

            let playlist = match created {
                Ok(p) => p,
                Err(e) => {
                    let _ = qt.queue(move |mut obj| {
                        obj.as_mut().set_loading(false);
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    });
                    return;
                }
            };

            if let Err(e) =
                library::add_track_to_playlist(app::state(), playlist.uuid.clone(), track).await
            {
                let _ = qt.queue(move |mut obj| {
                    obj.as_mut().set_loading(false);
                    obj.as_mut().set_error(QString::from(&e.to_string()));
                });
                return;
            }

            let refreshed = library::get_all_flattened_playlists(app::state()).await;

            let _ = qt.queue(move |mut obj| {
                if !obj.rust().tree_requests.is_current(token) {
                    return;
                }
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

    pub fn remove(mut self: Pin<&mut Self>, uuid: &QString) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let token = self.as_mut().rust_mut().tree_requests.start();
        let playlist_id = uuid.to_string();
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let user_id = match auth::get_session_user_id(app::state()).await {
                Ok(id) => id,
                Err(e) => {
                    let _ = qt.queue(move |mut obj| {
                        obj.as_mut().set_loading(false);
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    });
                    return;
                }
            };

            if let Err(e) =
                library::delete_playlist(app::state(), user_id, playlist_id.clone()).await
            {
                let _ = qt.queue(move |mut obj| {
                    obj.as_mut().set_loading(false);
                    obj.as_mut().set_error(QString::from(&e.to_string()));
                });
                return;
            }

            let refreshed = library::get_all_flattened_playlists(app::state()).await;

            let _ = qt.queue(move |mut obj| {
                if !obj.rust().tree_requests.is_current(token) {
                    return;
                }
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

    pub fn update_metadata(
        mut self: Pin<&mut Self>,
        uuid: &QString,
        title: &QString,
        description: &QString,
        is_public: bool,
    ) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let tree_token = self.as_mut().rust_mut().tree_requests.start();
        let playlist_token = self.as_mut().rust_mut().playlist_requests.start();
        let qt = self.qt_thread();
        let playlist_id = uuid.to_string();
        let new_title = title.to_string();
        let new_description = description.to_string();
        let access_type = (if is_public { "PUBLIC" } else { "UNLISTED" }).to_string();

        klang_core::runtime::spawn(async move {
            let updated = library::update_playlist(
                app::state(),
                playlist_id.clone(),
                new_title,
                new_description,
                access_type,
            )
            .await;

            if let Err(e) = updated {
                let _ = qt.queue(move |mut obj| {
                    obj.as_mut().set_loading(false);
                    obj.as_mut().set_error(QString::from(&e.to_string()));
                });
                return;
            }

            // Metadata shows up both in the sidebar row and, if this
            // playlist is currently open, its header.
            let (refreshed, details) = tokio::join!(
                library::get_all_flattened_playlists(app::state()),
                metadata::get_playlist_details(app::state(), playlist_id.clone()),
            );

            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_loading(false);
                if obj.rust().tree_requests.is_current(tree_token) {
                    match refreshed {
                        Ok(items) => {
                            let rows: Vec<_> = items.iter().map(folder_item).collect();
                            let json =
                                serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into());
                            obj.as_mut().set_playlists_json(QString::from(&json));
                        }
                        Err(e) => {
                            obj.as_mut().set_error(QString::from(&e.to_string()));
                        }
                    }
                }
                if obj.rust().playlist_requests.is_current(playlist_token) {
                    if let Ok(raw) = details {
                        let header = playlist_header(&playlist_id, &raw);
                        let json = serde_json::to_string(&header).unwrap_or_else(|_| "{}".into());
                        obj.as_mut().set_playlist_json(QString::from(&json));
                    }
                }
            });
        });
    }

    pub fn move_track(mut self: Pin<&mut Self>, uuid: &QString, from_index: i32, to_index: i32) {
        if from_index < 0 || to_index < 0 || from_index == to_index {
            return;
        }
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let token = self.as_mut().rust_mut().playlist_requests.start();
        let qt = self.qt_thread();
        let playlist_id = uuid.to_string();
        let from = from_index as u32;
        let to = to_index as u32;

        klang_core::runtime::spawn(async move {
            let moved =
                library::move_playlist_track(app::state(), playlist_id.clone(), from, to).await;

            if let Err(e) = moved {
                let _ = qt.queue(move |mut obj| {
                    obj.as_mut().set_loading(false);
                    obj.as_mut().set_error(QString::from(&e.to_string()));
                });
                return;
            }

            let (details, tracks) = tokio::join!(
                metadata::get_playlist_details(app::state(), playlist_id.clone()),
                library::get_playlist_tracks(app::state(), app::handle(), playlist_id.clone()),
            );

            let _ = qt.queue(move |mut obj| {
                if !obj.rust().playlist_requests.is_current(token) {
                    return;
                }
                obj.as_mut().set_loading(false);

                if let Ok(raw) = details {
                    let header = playlist_header(&playlist_id, &raw);
                    let json = serde_json::to_string(&header).unwrap_or_else(|_| "{}".into());
                    obj.as_mut().set_playlist_json(QString::from(&json));
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

    pub fn create_folder(mut self: Pin<&mut Self>, name: &QString) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let token = self.as_mut().rust_mut().tree_requests.start();
        let qt = self.qt_thread();
        let name = name.to_string();

        klang_core::runtime::spawn(async move {
            let created = library::create_playlist_folder(
                app::state(),
                "root".to_string(),
                name,
                String::new(),
            )
            .await;

            if let Err(e) = created {
                let _ = qt.queue(move |mut obj| {
                    obj.as_mut().set_loading(false);
                    obj.as_mut().set_error(QString::from(&e.to_string()));
                });
                return;
            }

            let refreshed = library::get_all_flattened_playlists(app::state()).await;
            let _ = qt.queue(move |mut obj| {
                if !obj.rust().tree_requests.is_current(token) {
                    return;
                }
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

    pub fn rename_folder(mut self: Pin<&mut Self>, id: &QString, name: &QString) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let token = self.as_mut().rust_mut().tree_requests.start();
        let qt = self.qt_thread();
        let folder_trn = format!("trn:folder:{}", id.to_string());
        let new_name = name.to_string();

        klang_core::runtime::spawn(async move {
            let renamed =
                library::rename_playlist_folder(app::state(), folder_trn, new_name).await;

            if let Err(e) = renamed {
                let _ = qt.queue(move |mut obj| {
                    obj.as_mut().set_loading(false);
                    obj.as_mut().set_error(QString::from(&e.to_string()));
                });
                return;
            }

            let refreshed = library::get_all_flattened_playlists(app::state()).await;
            let _ = qt.queue(move |mut obj| {
                if !obj.rust().tree_requests.is_current(token) {
                    return;
                }
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

    pub fn delete_folder(mut self: Pin<&mut Self>, id: &QString) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let token = self.as_mut().rust_mut().tree_requests.start();
        let qt = self.qt_thread();
        let folder_trn = format!("trn:folder:{}", id.to_string());

        klang_core::runtime::spawn(async move {
            let deleted = library::delete_playlist_folder(app::state(), folder_trn).await;

            if let Err(e) = deleted {
                let _ = qt.queue(move |mut obj| {
                    obj.as_mut().set_loading(false);
                    obj.as_mut().set_error(QString::from(&e.to_string()));
                });
                return;
            }

            let refreshed = library::get_all_flattened_playlists(app::state()).await;
            let _ = qt.queue(move |mut obj| {
                if !obj.rust().tree_requests.is_current(token) {
                    return;
                }
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

    pub fn move_to_folder(mut self: Pin<&mut Self>, playlist_uuid: &QString, folder_id: &QString) {
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let token = self.as_mut().rust_mut().tree_requests.start();
        let qt = self.qt_thread();
        let playlist_trn = format!("trn:playlist:{}", playlist_uuid.to_string());
        // TIDAL has no concept of an empty folderId for "top level" — it
        // wants the literal string "root", confirmed against the web client.
        let target = match folder_id.to_string() {
            id if id.is_empty() => "root".to_string(),
            id => id,
        };

        klang_core::runtime::spawn(async move {
            let moved = library::move_playlist_to_folder(app::state(), target, playlist_trn).await;

            if let Err(e) = moved {
                let _ = qt.queue(move |mut obj| {
                    obj.as_mut().set_loading(false);
                    obj.as_mut().set_error(QString::from(&e.to_string()));
                });
                return;
            }

            let refreshed = library::get_all_flattened_playlists(app::state()).await;
            let _ = qt.queue(move |mut obj| {
                if !obj.rust().tree_requests.is_current(token) {
                    return;
                }
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
}
