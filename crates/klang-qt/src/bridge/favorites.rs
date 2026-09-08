//! Favourite state for every entity kind.
//!
//! The ids are loaded once and kept in memory so a heart renders without a
//! round-trip per row; writes update the set optimistically and roll back if
//! TIDAL refuses.

use crate::core as app;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use klang_core::api::library;
use std::collections::HashSet;
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
        #[qproperty(bool, loading)]
        #[qproperty(QString, error)]
        /// Bumped on every change so QML bindings re-evaluate; the sets
        /// themselves live in Rust and are queried through `is_*`.
        #[qproperty(i32, revision)]
        type FavoritesController = super::FavoritesControllerRust;

        /// Load every favourite id for the signed-in user. Call once at start.
        #[qinvokable]
        fn load(self: Pin<&mut FavoritesController>, user_id: i64);

        #[qinvokable]
        fn is_track(self: &FavoritesController, id: i64) -> bool;
        #[qinvokable]
        fn is_album(self: &FavoritesController, id: i64) -> bool;
        #[qinvokable]
        fn is_artist(self: &FavoritesController, id: i64) -> bool;
        #[qinvokable]
        fn is_playlist(self: &FavoritesController, uuid: &QString) -> bool;

        /// Add when absent, remove when present.
        #[qinvokable]
        fn toggle_track(self: Pin<&mut FavoritesController>, id: i64);
        #[qinvokable]
        fn toggle_album(self: Pin<&mut FavoritesController>, id: i64);
        #[qinvokable]
        fn toggle_artist(self: Pin<&mut FavoritesController>, id: i64);
        #[qinvokable]
        fn toggle_playlist(self: Pin<&mut FavoritesController>, uuid: &QString);
    }

    impl cxx_qt::Threading for FavoritesController {}
}

#[derive(Default)]
struct Sets {
    tracks: HashSet<i64>,
    albums: HashSet<i64>,
    artists: HashSet<i64>,
    playlists: HashSet<String>,
}

#[derive(Default)]
pub struct FavoritesControllerRust {
    loading: bool,
    error: QString,
    revision: i32,
    user_id: i64,
    sets: Mutex<Sets>,
}

/// Which set a toggle acts on. Playlists key on a uuid, the rest on an id.
#[derive(Clone, Copy)]
enum Kind {
    Track,
    Album,
    Artist,
}

impl qobject::FavoritesController {
    pub fn load(mut self: Pin<&mut Self>, user_id: i64) {
        if user_id == 0 {
            return;
        }
        self.as_mut().rust_mut().user_id = user_id;
        self.as_mut().set_loading(true);
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let result = library::get_all_favorite_ids(app::state(), user_id as u64).await;
            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_loading(false);
                match result {
                    Ok(ids) => {
                        {
                            let mut sets = obj.rust().sets.lock().unwrap();
                            sets.tracks = ids.tracks.iter().map(|&i| i as i64).collect();
                            sets.albums = ids.albums.iter().map(|&i| i as i64).collect();
                            sets.artists = ids.artists.iter().map(|&i| i as i64).collect();
                            sets.playlists = ids.playlists.into_iter().collect();
                        }
                        obj.bump();
                    }
                    Err(e) => obj.as_mut().set_error(QString::from(&e.to_string())),
                }
            });
        });
    }

    pub fn is_track(&self, id: i64) -> bool {
        self.rust().sets.lock().unwrap().tracks.contains(&id)
    }

    pub fn is_album(&self, id: i64) -> bool {
        self.rust().sets.lock().unwrap().albums.contains(&id)
    }

    pub fn is_artist(&self, id: i64) -> bool {
        self.rust().sets.lock().unwrap().artists.contains(&id)
    }

    pub fn is_playlist(&self, uuid: &QString) -> bool {
        self.rust()
            .sets
            .lock()
            .unwrap()
            .playlists
            .contains(&uuid.to_string())
    }

    pub fn toggle_track(self: Pin<&mut Self>, id: i64) {
        self.toggle(Kind::Track, id);
    }

    pub fn toggle_album(self: Pin<&mut Self>, id: i64) {
        self.toggle(Kind::Album, id);
    }

    pub fn toggle_artist(self: Pin<&mut Self>, id: i64) {
        self.toggle(Kind::Artist, id);
    }

    pub fn toggle_playlist(mut self: Pin<&mut Self>, uuid: &QString) {
        let uuid = uuid.to_string();
        let user_id = self.rust().user_id;
        if user_id == 0 || uuid.is_empty() {
            return;
        }

        let adding = {
            let mut sets = self.rust().sets.lock().unwrap();
            if sets.playlists.remove(&uuid) {
                false
            } else {
                sets.playlists.insert(uuid.clone());
                true
            }
        };
        self.as_mut().bump();
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let state = app::state();
            let user = user_id as u64;
            let result = if adding {
                library::add_favorite_playlist(state, user, uuid.clone()).await
            } else {
                library::remove_favorite_playlist(state, user, uuid.clone()).await
            };
            if let Err(e) = result {
                let msg = e.to_string();
                let _ = qt.queue(move |mut obj| {
                    // Put the optimistic change back.
                    {
                        let mut sets = obj.rust().sets.lock().unwrap();
                        if adding {
                            sets.playlists.remove(&uuid);
                        } else {
                            sets.playlists.insert(uuid);
                        }
                    }
                    obj.as_mut().set_error(QString::from(&msg));
                    obj.bump();
                });
            }
        });
    }

    /// Flip one id and reconcile with TIDAL, rolling back on failure.
    fn toggle(mut self: Pin<&mut Self>, kind: Kind, id: i64) {
        let user_id = self.rust().user_id;
        if user_id == 0 || id == 0 {
            return;
        }

        let adding = {
            let mut sets = self.rust().sets.lock().unwrap();
            let set = match kind {
                Kind::Track => &mut sets.tracks,
                Kind::Album => &mut sets.albums,
                Kind::Artist => &mut sets.artists,
            };
            if set.remove(&id) {
                false
            } else {
                set.insert(id);
                true
            }
        };
        self.as_mut().bump();
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let state = app::state();
            let user = user_id as u64;
            let target = id as u64;
            let result = match (kind, adding) {
                (Kind::Track, true) => library::add_favorite_track(state, user, target).await,
                (Kind::Track, false) => library::remove_favorite_track(state, user, target).await,
                (Kind::Album, true) => library::add_favorite_album(state, user, target).await,
                (Kind::Album, false) => library::remove_favorite_album(state, user, target).await,
                (Kind::Artist, true) => library::add_favorite_artist(state, user, target).await,
                (Kind::Artist, false) => library::remove_favorite_artist(state, user, target).await,
            };
            if let Err(e) = result {
                let msg = e.to_string();
                let _ = qt.queue(move |mut obj| {
                    {
                        let mut sets = obj.rust().sets.lock().unwrap();
                        let set = match kind {
                            Kind::Track => &mut sets.tracks,
                            Kind::Album => &mut sets.albums,
                            Kind::Artist => &mut sets.artists,
                        };
                        if adding {
                            set.remove(&id);
                        } else {
                            set.insert(id);
                        }
                    }
                    obj.as_mut().set_error(QString::from(&msg));
                    obj.bump();
                });
            }
        });
    }

    fn bump(mut self: Pin<&mut Self>) {
        let next = self.revision().wrapping_add(1);
        self.set_revision(next);
    }
}
