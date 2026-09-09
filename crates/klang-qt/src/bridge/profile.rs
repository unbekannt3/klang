//! The signed-in user's TIDAL profile: header data, public playlists, and
//! editing (name/handle/bio/links/picture).
//!
//! One controller is shared between the header's avatar menu and the profile
//! page (see Main.qml) rather than each owning its own: TIDAL's profile
//! endpoint is the only source for the avatar shown in the header, so both
//! consumers read the same `profile_json` instead of fetching it twice.

use crate::bridge::RequestSeq;
use crate::core as app;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QByteArray, QString};
use klang_core::api::profile;
use klang_core::tidal_api::{ExternalLink, Profile, ProfileArtFile, ProfilePlaylist};
use klang_core::SoneError;
use serde_json::{json, Value};
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
        #[qproperty(bool, saving)]
        #[qproperty(bool, not_found)]
        #[qproperty(QString, error)]
        #[qproperty(QString, profile_json)]
        type ProfileController = super::ProfileControllerRust;

        /// Load a user's profile. TIDAL serves the signed-in user's own
        /// profile and a public one through the same endpoint.
        #[qinvokable]
        fn load(self: Pin<&mut ProfileController>, user_id: i64);

        /// Save name/handle, bio and external links in one request sequence,
        /// mirroring upstream's edit modal: meta first (a validating dry run,
        /// then the real update), then bio, then links — stopping at the
        /// first failure. Reloads the profile on success.
        #[qinvokable]
        fn save(
            self: Pin<&mut ProfileController>,
            artist_id: i64,
            name: &QString,
            handle: &QString,
            bio: &QString,
            links_json: &QString,
        );

        /// Replace the profile picture with the image at `file_path` on
        /// disk. Reloads the profile on success.
        #[qinvokable]
        fn upload_picture(self: Pin<&mut ProfileController>, artist_id: i64, file_path: &QString);

        /// Remove the profile picture. Reloads the profile on success.
        #[qinvokable]
        fn delete_picture(self: Pin<&mut ProfileController>, artist_id: i64);
    }

    impl cxx_qt::Threading for ProfileController {}
}

#[derive(Default)]
pub struct ProfileControllerRust {
    loading: bool,
    saving: bool,
    not_found: bool,
    error: QString,
    profile_json: QString,
    /// The last profile loaded, kept to diff against on save (which fields
    /// actually changed) and to know which user id to reload afterwards.
    current: Option<Profile>,
    /// The header avatar and the profile page share this controller, so a
    /// profile the user has navigated away from must not win the race.
    requests: RequestSeq,
}

/// Pick the hero photo href: the smallest rendition at least 640 wide, or
/// the widest available, or the first entry when widths are unknown.
/// `picture_files` is already sorted desc by width and each href is a full
/// URL — see `Profile::picture_files`.
fn pick_hero_image(files: &[ProfileArtFile]) -> Option<String> {
    if files.is_empty() {
        return None;
    }
    let with_width: Vec<&ProfileArtFile> = files.iter().filter(|f| f.width.is_some()).collect();
    if with_width.is_empty() {
        return Some(files[0].href.clone());
    }
    let mut at_least_640: Vec<&&ProfileArtFile> = with_width
        .iter()
        .filter(|f| f.width.unwrap() >= 640)
        .collect();
    at_least_640.sort_by_key(|f| f.width.unwrap());
    if let Some(f) = at_least_640.first() {
        return Some(f.href.clone());
    }
    with_width
        .iter()
        .max_by_key(|f| f.width.unwrap())
        .map(|f| f.href.clone())
}

/// Pick the avatar href: TIDAL returns both 1:1 and 16:9 renditions, so the
/// round avatar needs a square one specifically. Prefers the smallest square
/// (the list is sorted desc by width); falls back to the smallest overall
/// when no square rendition is present.
fn pick_avatar_href(files: &[ProfileArtFile]) -> Option<String> {
    if files.is_empty() {
        return None;
    }
    let squares: Vec<&ProfileArtFile> = files
        .iter()
        .filter(|f| f.width.is_some() && f.width == f.height)
        .collect();
    let pool: Vec<&ProfileArtFile> = if squares.is_empty() { files.iter().collect() } else { squares };
    pool.last().map(|f| f.href.clone())
}

fn playlist_row(pl: &ProfilePlaylist, owner_name: &str) -> Value {
    json!({
        "id": pl.id,
        "title": pl.title,
        "subtitle": owner_name,
        "image": pl.cover_url.clone().unwrap_or_default(),
        "kind": "playlist",
        "numberOfTracks": pl.number_of_tracks.unwrap_or(0),
    })
}

fn external_link_row(link: &ExternalLink) -> Value {
    json!({ "href": link.href, "linkType": link.link_type })
}

/// Flatten a `Profile` for QML: pre-resolved avatar/hero URLs, playlists as
/// ready-to-use card rows, and external links passed through as-is so the
/// UI can split social handles from the homepage link itself.
fn profile_row(p: &Profile) -> Value {
    let playlists: Vec<_> = p.public_playlists.iter().map(|pl| playlist_row(pl, &p.name)).collect();
    let links: Vec<_> = p.external_links.iter().map(external_link_row).collect();
    json!({
        "userId": p.user_id,
        "artistId": p.artist_id.unwrap_or(0),
        "hasArtistId": p.artist_id.is_some(),
        "name": p.name,
        "handle": p.handle.clone().unwrap_or_default(),
        "bio": p.bio.clone().unwrap_or_default(),
        "avatarUrl": pick_avatar_href(&p.picture_files).unwrap_or_default(),
        "heroUrl": pick_hero_image(&p.picture_files).unwrap_or_default(),
        "fanCount": p.fan_count.unwrap_or(0),
        "hasFanCount": p.fan_count.is_some(),
        "externalLinks": links,
        "playlists": playlists,
    })
}

/// Runs the edit-modal save sequence against the facade: meta (dry run, then
/// real) only for fields that actually changed, then bio, then links —
/// stopping at the first error, same as upstream's modal.
async fn save_profile(
    artist_id: u64,
    name: &str,
    handle: &str,
    bio: &str,
    links: Vec<ExternalLink>,
    original: Option<&Profile>,
) -> Result<(), SoneError> {
    let name_changed = original.map(|p| p.name != name).unwrap_or(true);
    let handle_changed = original
        .map(|p| p.handle.as_deref().unwrap_or("") != handle)
        .unwrap_or(true);
    let bio_changed = original.map(|p| p.bio.as_deref().unwrap_or("") != bio).unwrap_or(true);

    if name_changed || handle_changed {
        let name_arg = name_changed.then(|| name.to_string());
        let handle_arg = handle_changed.then(|| handle.to_string());
        profile::update_profile_meta(app::state(), artist_id, name_arg.clone(), handle_arg.clone(), true)
            .await?;
        profile::update_profile_meta(app::state(), artist_id, name_arg, handle_arg, false).await?;
    }

    if bio_changed {
        // Keyed by the artist id, not `Profile.bio_id` — TIDAL creates or
        // updates the biography resource at PATCH /artistBiographies/{artistId}.
        profile::update_profile_bio(app::state(), artist_id.to_string(), bio.to_string()).await?;
    }

    profile::update_profile_links(app::state(), artist_id, links).await
}

/// Reads the image at `path` and base64-encodes it via `QByteArray` — this
/// crate has no `base64` dependency of its own, unlike klang-core's facade,
/// which expects the encoded form.
fn read_image_base64(path: &str) -> Result<String, SoneError> {
    let bytes = std::fs::read(path).map_err(|e| SoneError::Io(e.to_string()))?;
    let encoded = QByteArray::from(bytes.as_slice()).to_base64(Default::default());
    Ok(encoded.to_string())
}

impl qobject::ProfileController {
    pub fn load(mut self: Pin<&mut Self>, user_id: i64) {
        let token = self.as_mut().rust_mut().requests.start();
        self.as_mut().set_loading(true);
        self.as_mut().set_not_found(false);
        self.as_mut().set_error(QString::from(""));
        let qt = self.qt_thread();
        let uid = user_id.max(0) as u64;

        klang_core::runtime::spawn(async move {
            let result = profile::get_profile(app::state(), uid).await;
            let _ = qt.queue(move |mut obj| {
                if !obj.rust().requests.is_current(token) {
                    return;
                }
                match result {
                    Ok(p) => {
                        let json = serde_json::to_string(&profile_row(&p)).unwrap_or_else(|_| "{}".into());
                        obj.as_mut().set_profile_json(QString::from(&json));
                        obj.as_mut().rust_mut().current = Some(p);
                    }
                    Err(SoneError::Api { status: 404, .. }) => {
                        obj.as_mut().set_not_found(true);
                    }
                    Err(e) => obj.as_mut().set_error(QString::from(&e.to_string())),
                }
                obj.as_mut().set_loading(false);
            });
        });
    }

    pub fn save(
        mut self: Pin<&mut Self>,
        artist_id: i64,
        name: &QString,
        handle: &QString,
        bio: &QString,
        links_json: &QString,
    ) {
        let artist_id = artist_id.max(0) as u64;
        let name = name.to_string();
        let handle = handle.to_string();
        let bio = bio.to_string();
        let links: Vec<ExternalLink> = serde_json::from_str(&links_json.to_string()).unwrap_or_default();
        let original = self.rust().current.clone();
        let user_id = original.as_ref().map(|p| p.user_id);

        self.as_mut().set_saving(true);
        self.as_mut().set_error(QString::from(""));
        let token = self.as_mut().rust_mut().requests.start();
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let result = save_profile(artist_id, &name, &handle, &bio, links, original.as_ref()).await;
            let reloaded = match (&result, user_id) {
                (Ok(()), Some(uid)) => Some(profile::get_profile(app::state(), uid).await),
                _ => None,
            };

            let _ = qt.queue(move |mut obj| {
                match result {
                    Ok(()) => {
                        if let (Some(Ok(p)), true) =
                            (reloaded, obj.rust().requests.is_current(token))
                        {
                            let json =
                                serde_json::to_string(&profile_row(&p)).unwrap_or_else(|_| "{}".into());
                            obj.as_mut().set_profile_json(QString::from(&json));
                            obj.as_mut().rust_mut().current = Some(p);
                        }
                    }
                    Err(e) => obj.as_mut().set_error(QString::from(&e.to_string())),
                }
                // Set last: QML closes the edit dialog on the falling edge of
                // `saving`, and it must see the refreshed profile by then.
                obj.as_mut().set_saving(false);
            });
        });
    }

    pub fn upload_picture(mut self: Pin<&mut Self>, artist_id: i64, file_path: &QString) {
        let artist_id = artist_id.max(0) as u64;
        let path = file_path.to_string();
        let user_id = self.rust().current.as_ref().map(|p| p.user_id);

        self.as_mut().set_saving(true);
        self.as_mut().set_error(QString::from(""));
        let token = self.as_mut().rust_mut().requests.start();
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let result = match read_image_base64(&path) {
                Ok(b64) => profile::upload_profile_picture(app::state(), artist_id, b64).await,
                Err(e) => Err(e),
            };
            let reloaded = match (&result, user_id) {
                (Ok(()), Some(uid)) => Some(profile::get_profile(app::state(), uid).await),
                _ => None,
            };

            let _ = qt.queue(move |mut obj| {
                match result {
                    Ok(()) => {
                        if let (Some(Ok(p)), true) =
                            (reloaded, obj.rust().requests.is_current(token))
                        {
                            let json =
                                serde_json::to_string(&profile_row(&p)).unwrap_or_else(|_| "{}".into());
                            obj.as_mut().set_profile_json(QString::from(&json));
                            obj.as_mut().rust_mut().current = Some(p);
                        }
                    }
                    Err(e) => obj.as_mut().set_error(QString::from(&e.to_string())),
                }
                obj.as_mut().set_saving(false);
            });
        });
    }

    pub fn delete_picture(mut self: Pin<&mut Self>, artist_id: i64) {
        let artist_id = artist_id.max(0) as u64;
        let user_id = self.rust().current.as_ref().map(|p| p.user_id);

        self.as_mut().set_saving(true);
        self.as_mut().set_error(QString::from(""));
        let token = self.as_mut().rust_mut().requests.start();
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let result = profile::delete_profile_picture(app::state(), artist_id).await;
            let reloaded = match (&result, user_id) {
                (Ok(()), Some(uid)) => Some(profile::get_profile(app::state(), uid).await),
                _ => None,
            };

            let _ = qt.queue(move |mut obj| {
                match result {
                    Ok(()) => {
                        if let (Some(Ok(p)), true) =
                            (reloaded, obj.rust().requests.is_current(token))
                        {
                            let json =
                                serde_json::to_string(&profile_row(&p)).unwrap_or_else(|_| "{}".into());
                            obj.as_mut().set_profile_json(QString::from(&json));
                            obj.as_mut().rust_mut().current = Some(p);
                        }
                    }
                    Err(e) => obj.as_mut().set_error(QString::from(&e.to_string())),
                }
                obj.as_mut().set_saving(false);
            });
        });
    }
}
