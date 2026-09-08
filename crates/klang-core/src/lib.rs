//! klang-core — the TIDAL client core, split out of lullabyX/sone.
//!
//! Everything here is UI-toolkit agnostic: the TIDAL API client, the GStreamer
//! playback pipeline, MPRIS, scrobbling, the disk cache, the MCP server and the
//! OBS overlay. The Qt layer talks to it through [`app::AppContext`], which
//! replaces upstream's `crate::app::AppHandle`.
//!
//! File paths under `src/` mirror upstream `src-tauri/src/` so that
//! `scripts/sync-core.sh` can three-way merge upstream fixes onto this tree.

// Everything the UI layer needs is `pub`. Upstream could keep most of this
// private because the 177 `#[tauri::command]` wrappers lived inside the crate;
// klang-qt sits outside it, so the same surface has to be reachable.
pub mod api;
pub mod app;
pub mod audio;
pub mod cache;
pub mod camelot;
pub mod embedded_config;
pub mod logging;
pub mod mcp;
pub mod overlay;
pub mod pipeline_probe;
pub mod runtime;
pub mod scrobble;
pub mod theme;
pub mod theme_config;
pub mod tidal_api;
pub mod tidal_report;
pub mod discord;
pub mod idle_inhibit;
pub mod signal_path;
#[cfg(target_os = "linux")]
pub mod mpris;
#[cfg(target_os = "linux")]
pub mod tray;

mod crypto;
mod embedded_lastfm;
mod embedded_librefm;
mod error;
mod http_util;
mod rate_gate;

pub use app::{AppContext, AppHandle, Emitter, EventSink, WaylandSurface, WindowShell};
pub use error::SoneError;
pub use runtime::KlangCore;
pub use signal_path::{SignalPath, SignalPathTracker};

use audio::{AudioDevice, AudioPlayer};
use cache::DiskCache;
use crypto::Crypto;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tidal_api::{AuthTokens, TidalClient};
use tokio::sync::Mutex;
mod defaults {
    pub fn yes() -> bool { true }
    pub fn volume() -> f32 { 1.0 }
    pub fn mcp_enabled() -> bool { false }
    pub fn mcp_port() -> u16 { 5577 }
    pub fn overlay_enabled() -> bool { false }
    pub fn overlay_port() -> u16 { 5578 }
    pub fn overlay_host() -> String { "127.0.0.1".to_string() }
    pub fn max_quality() -> String { "HI_RES_LOSSLESS".to_string() }
}

#[derive(Debug, Serialize, Deserialize, Clone, Default)]
pub struct LastfmCredentials {
    pub session_key: String,
    pub username: String,
}

#[derive(Debug, Serialize, Deserialize, Clone, Default)]
pub struct ListenBrainzCredentials {
    pub token: String,
    pub username: String,
}

#[derive(Debug, Serialize, Deserialize, Clone, Default)]
pub struct ScrobbleSettings {
    pub lastfm: Option<LastfmCredentials>,
    pub librefm: Option<LastfmCredentials>,
    pub listenbrainz: Option<ListenBrainzCredentials>,
}

/// Tracks which embedded credential pair the saved tokens belong to,
/// so refresh-token requests use the matching client_id/secret.
/// Only relevant when the user has not provided custom credentials.
#[derive(Debug, Serialize, Deserialize, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AuthMethod {
    LoginCode,
    Pkce,
}

impl Default for AuthMethod {
    fn default() -> Self {
        Self::LoginCode
    }
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum ProxyType {
    Http,
    Socks5,
}

impl Default for ProxyType {
    fn default() -> Self {
        Self::Http
    }
}

#[derive(Debug, Serialize, Deserialize, Clone, Default)]
pub struct ProxySettings {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub proxy_type: ProxyType,
    #[serde(default)]
    pub host: String,
    #[serde(default)]
    pub port: u16,
    #[serde(default)]
    pub username: Option<String>,
    #[serde(default)]
    pub password: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Settings {
    pub auth_tokens: Option<AuthTokens>,
    #[serde(default = "defaults::volume")]
    pub volume: f32,
    pub last_track_id: Option<u64>,
    #[serde(default)]
    pub client_id: String,
    #[serde(default)]
    pub client_secret: String,
    /// Which embedded credential pair to use for refresh when `client_id`
    /// is empty. Defaults to LoginCode for backward compatibility with
    /// existing installs.
    #[serde(default)]
    pub auth_method: AuthMethod,
    #[serde(default)]
    pub minimize_to_tray: bool,
    #[serde(default)]
    pub decorations: bool,
    /// One-shot flag: was the user migrated from native chrome to the
    /// custom React titlebar? `false` (or missing) on existing installs
    /// triggers a silent flip of `decorations` to `false` at startup.
    #[serde(default)]
    pub titlebar_migration_v1: bool,
    #[serde(default)]
    pub volume_normalization: bool,
    #[serde(default)]
    pub exclusive_mode: bool,
    #[serde(default)]
    pub exclusive_device: Option<String>,
    #[serde(default)]
    pub bit_perfect: bool,
    #[serde(default = "defaults::yes")]
    pub gapless: bool,
    #[serde(default = "defaults::max_quality")]
    pub max_quality: String,
    #[serde(default)]
    pub scrobble: ScrobbleSettings,
    #[serde(default)]
    pub proxy: ProxySettings,
    #[serde(default = "defaults::yes")]
    pub discord_rpc: bool,
    #[serde(default)]
    pub discord_status_text: String,
    /// How many times we've shown the "legacy sign-in" notice to users still
    /// on the device-code (LoginCode) auth method. Caps at 5; never resets.
    #[serde(default)]
    pub legacy_auth_notice_count: u8,
    #[serde(default = "defaults::mcp_enabled")]
    pub mcp_enabled: bool,
    #[serde(default = "defaults::mcp_port")]
    pub mcp_port: u16,
    /// Persistent UUID token for the MCP URL path. Empty string means
    /// "not yet generated" — bootstrap will populate and save on first run.
    #[serde(default)]
    pub mcp_token: String,
    #[serde(default = "defaults::overlay_enabled")]
    pub overlay_enabled: bool,
    #[serde(default = "defaults::overlay_port")]
    pub overlay_port: u16,
    #[serde(default = "defaults::overlay_host")]
    pub overlay_host: String,
    /// Report plays to TIDAL (Recently Played). On by default; disable in
    /// Settings → Scrobbling.
    #[serde(default = "defaults::yes")]
    pub report_plays: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            auth_tokens: None,
            volume: 1.0,
            last_track_id: None,
            client_id: String::new(),
            client_secret: String::new(),
            auth_method: AuthMethod::default(),
            minimize_to_tray: false,
            decorations: false,
            titlebar_migration_v1: true,
            volume_normalization: false,
            exclusive_mode: false,
            exclusive_device: None,
            bit_perfect: false,
            gapless: true,
            max_quality: "HI_RES_LOSSLESS".to_string(),
            scrobble: Default::default(),
            proxy: Default::default(),
            discord_rpc: true,
            discord_status_text: String::new(),
            legacy_auth_notice_count: 0,
            mcp_enabled: false,
            mcp_port: 5577,
            mcp_token: String::new(),
            overlay_enabled: false,
            overlay_port: 5578,
            overlay_host: "127.0.0.1".to_string(),
            report_plays: true,
        }
    }
}

pub struct AppState {
    pub audio_player: Arc<AudioPlayer>,
    pub pipeline_probe: Arc<crate::pipeline_probe::PipelineProbe>,
    pub tidal_client: Mutex<TidalClient>,
    pub settings_path: PathBuf,
    pub cache_dir: PathBuf,
    pub disk_cache: DiskCache,
    pub crypto: Arc<Crypto>,
    pub minimize_to_tray: AtomicBool,
    pub decorations: AtomicBool,
    pub volume_normalization: AtomicBool,
    pub exclusive_mode: AtomicBool,
    pub bit_perfect: AtomicBool,
    pub gapless: AtomicBool,
    pub max_quality: std::sync::Mutex<String>,
    pub exclusive_device: std::sync::Mutex<Option<String>>,
    pub cached_audio_devices: std::sync::Mutex<Option<Vec<AudioDevice>>>,
    /// Current track's selected replay gain (dB) stored as f64 bits. NAN = no data.
    /// Album or track gain depending on playback context.
    pub last_replay_gain: AtomicU64,
    /// Current track's selected peak amplitude (linear) stored as f64 bits. NAN = no data.
    /// Album or track peak depending on playback context.
    pub last_peak_amplitude: AtomicU64,
    #[cfg(target_os = "linux")]
    pub mpris: mpris::MprisHandle,
    /// Set once the ksni tray registers on D-Bus. Upstream kept this in Tauri's
    /// managed state; without `app.manage()` it lives here.
    #[cfg(target_os = "linux")]
    pub tray_handle: std::sync::Mutex<Option<tray::TrayHandle>>,
    pub scrobble_manager: scrobble::ScrobbleManager,
    pub tidal_reporter: tidal_report::TidalReporter,
    pub discord: discord::DiscordHandle,
    pub idle_inhibitor: Mutex<idle_inhibit::IdleInhibitor>,
    pub mcp_state: crate::mcp::McpStateRef,
    pub mcp_handle: Mutex<Option<crate::mcp::McpHandle>>,
    pub overlay_state: crate::overlay::OverlayStateRef,
    pub overlay_handle: Mutex<Option<crate::overlay::OverlayHandle>>,
    pub signal_path: Arc<SignalPathTracker>,
}

pub fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

/// Write refreshed tokens back into the stored settings. Called from every
/// refresh, including the automatic one after a 401 — without it the stored
/// access token stays stale and each launch burns a 401 before the first
/// request succeeds.
fn persist_auth_tokens(path: &Path, crypto: &Crypto, tokens: &AuthTokens) {
    let mut settings = fs::read(path)
        .ok()
        .and_then(|data| crypto.decrypt(&data).ok())
        .and_then(|plain| serde_json::from_slice::<Settings>(&plain).ok())
        .unwrap_or_default();
    settings.auth_tokens = Some(tokens.clone());

    let write = || -> Result<(), SoneError> {
        let json = serde_json::to_string_pretty(&settings)?;
        let encrypted = crypto.encrypt(json.as_bytes())?;
        fs::write(path, encrypted)?;
        Ok(())
    };
    if let Err(e) = write() {
        log::warn!("Failed to persist refreshed auth tokens: {e}");
    }
}

impl AppState {
    fn new(app_handle: crate::app::AppHandle) -> Self {
        // Get config dir
        // One source of truth, so $KLANG_CONFIG_DIR reaches settings, cache,
        // crypto key and logs alike.
        let config_dir = crate::runtime::config_dir();
        fs::create_dir_all(&config_dir).ok();

        let settings_path = config_dir.join("settings.json");
        let cache_dir = config_dir.join("cache");
        fs::create_dir_all(&cache_dir).ok();

        // Initialize encryption
        let crypto = match Crypto::new(&config_dir) {
            Ok(c) => Arc::new(c),
            Err(e) => {
                log::error!("Failed to initialize crypto: {e}. Data-at-rest encryption disabled.");
                panic!("Crypto initialization failed: {e}");
            }
        };

        let disk_cache = DiskCache::new(&cache_dir, crypto.clone());

        // Load preferences from saved settings (decrypt if needed)
        let mut saved = fs::read(&settings_path)
            .ok()
            .and_then(|data| crypto.decrypt(&data).ok())
            .and_then(|plain| String::from_utf8(plain).ok())
            .and_then(|s| serde_json::from_str::<Settings>(&s).ok());

        // One-shot custom-titlebar migration: existing installs had
        // `decorations: true` (native GTK chrome); silent-flip to false so
        // the custom React titlebar is shown by default. The toggle in
        // Settings remains as an escape hatch.
        if let Some(ref mut s) = saved {
            if !s.titlebar_migration_v1 {
                log::info!("[migration] custom-titlebar v1: flipping decorations to false");
                s.decorations = false;
                s.titlebar_migration_v1 = true;
                if let Ok(json) = serde_json::to_string_pretty(s) {
                    if let Ok(encrypted) = crypto.encrypt(json.as_bytes()) {
                        if let Err(e) = fs::write(&settings_path, encrypted) {
                            log::warn!(
                                "[migration] failed to persist titlebar_migration_v1: {e}"
                            );
                        }
                    }
                }
            }
        }

        // Eager migration: if settings exist but aren't encrypted, re-save encrypted
        if settings_path.exists() {
            if let Ok(raw) = fs::read(&settings_path) {
                if !crypto::is_encrypted(&raw) {
                    if let Some(ref settings) = saved {
                        if let Ok(json) = serde_json::to_string_pretty(settings) {
                            if let Ok(encrypted) = crypto.encrypt(json.as_bytes()) {
                                if let Err(e) = fs::write(&settings_path, encrypted) {
                                    log::warn!("Failed to migrate settings to encrypted: {e}");
                                } else {
                                    log::info!("Migrated settings.json to encrypted format");
                                }
                            }
                        }
                    }
                }
            }
        }

        let minimize_to_tray = saved.as_ref().map(|s| s.minimize_to_tray).unwrap_or(false);
        let decorations = saved.as_ref().map(|s| s.decorations).unwrap_or(false);
        let volume_normalization = saved
            .as_ref()
            .map(|s| s.volume_normalization)
            .unwrap_or(false);
        let exclusive_mode = saved.as_ref().map(|s| s.exclusive_mode).unwrap_or(false);
        let bit_perfect = saved.as_ref().map(|s| s.bit_perfect).unwrap_or(false);
        let gapless = saved.as_ref().map(|s| s.gapless).unwrap_or(true);
        let exclusive_device = saved.as_ref().and_then(|s| s.exclusive_device.clone());
        let max_quality = saved
            .as_ref()
            .map(|s| s.max_quality.clone())
            .unwrap_or_else(defaults::max_quality);

        let proxy_settings = saved.as_ref().map(|s| s.proxy.clone()).unwrap_or_default();
        let scrobble_http_client = crate::tidal_api::build_http_client(&proxy_settings)
            .unwrap_or_else(|_| {
                reqwest::Client::builder()
                    .timeout(std::time::Duration::from_secs(30))
                    .build()
                    .unwrap()
            });
        let scrobble_manager = scrobble::ScrobbleManager::new(
            app_handle.clone(),
            crypto.clone(),
            &config_dir,
            scrobble_http_client.clone(),
        );

        let report_plays = saved.as_ref().map(|s| s.report_plays).unwrap_or(true);
        let tidal_reporter = tidal_report::TidalReporter::new(
            app_handle.clone(),
            crypto.clone(),
            &config_dir,
            scrobble_http_client,
            report_plays,
        );

        let discord_rpc_enabled = saved.as_ref().map(|s| s.discord_rpc).unwrap_or(true);
        let discord_status_text = saved
            .as_ref()
            .map(|s| s.discord_status_text.clone())
            .unwrap_or_default();
        let discord_handle = discord::DiscordHandle::new();
        discord_handle.send(discord::DiscordCommand::SetStatusText {
            text: discord_status_text,
        });
        if discord_rpc_enabled {
            discord_handle.send(discord::DiscordCommand::Connect);
        }

        let signal_path = Arc::new(SignalPathTracker::new(app_handle.clone()));
        signal_path.set_audio_modes(exclusive_mode, bit_perfect);
        signal_path.set_normalization_enabled(volume_normalization);

        let audio_player = Arc::new(AudioPlayer::new(
            app_handle.clone(),
            Arc::clone(&signal_path),
        ));
        let pipeline_probe = Arc::new(crate::pipeline_probe::PipelineProbe::new(
            Arc::clone(&signal_path),
            Arc::clone(&audio_player),
        ));

        let mut tidal_client = TidalClient::new(&proxy_settings);
        tidal_client.set_token_persist({
            let settings_path = settings_path.clone();
            let crypto = Arc::clone(&crypto);
            Arc::new(move |tokens: &AuthTokens| {
                persist_auth_tokens(&settings_path, &crypto, tokens);
            })
        });

        Self {
            audio_player,
            pipeline_probe,
            tidal_client: Mutex::new(tidal_client),
            settings_path,
            cache_dir,
            disk_cache,
            crypto,
            minimize_to_tray: AtomicBool::new(minimize_to_tray),
            decorations: AtomicBool::new(decorations),
            volume_normalization: AtomicBool::new(volume_normalization),
            exclusive_mode: AtomicBool::new(exclusive_mode),
            bit_perfect: AtomicBool::new(bit_perfect),
            gapless: AtomicBool::new(gapless),
            max_quality: std::sync::Mutex::new(max_quality),
            exclusive_device: std::sync::Mutex::new(exclusive_device),
            cached_audio_devices: std::sync::Mutex::new(None),
            last_replay_gain: AtomicU64::new(f64::NAN.to_bits()),
            last_peak_amplitude: AtomicU64::new(f64::NAN.to_bits()),
            #[cfg(target_os = "linux")]
            mpris: mpris::MprisHandle::new(app_handle),
            #[cfg(target_os = "linux")]
            tray_handle: std::sync::Mutex::new(None),
            scrobble_manager,
            tidal_reporter,
            discord: discord_handle,
            idle_inhibitor: Mutex::new(idle_inhibit::IdleInhibitor::new()),
            mcp_state: crate::mcp::new_state(),
            mcp_handle: Mutex::new(None),
            overlay_state: {
                let (s, _rx, _theme_rx) = crate::overlay::new_state();
                s
            },
            overlay_handle: Mutex::new(None),
            signal_path,
        }
    }

    pub fn load_settings(&self) -> Option<Settings> {
        let data = fs::read(&self.settings_path).ok()?;
        let plain = self.crypto.decrypt(&data).ok()?;
        let text = String::from_utf8(plain).ok()?;
        serde_json::from_str(&text).ok()
    }

    pub fn save_settings(&self, settings: &Settings) -> Result<(), SoneError> {
        let json = serde_json::to_string_pretty(settings)?;
        let encrypted = self.crypto.encrypt(json.as_bytes())?;
        fs::write(&self.settings_path, encrypted)?;
        Ok(())
    }

    // ---- Persistent state (not cache — survives restarts) ----

    pub fn read_state_file(&self, name: &str) -> Option<String> {
        let path = self.cache_dir.join(name);
        let data = match fs::read(&path) {
            Ok(d) => d,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return None,
            Err(e) => {
                log::warn!("Failed to read state file {name}: {e}");
                return None;
            }
        };
        let plain = match self.crypto.decrypt(&data) {
            Ok(p) => p,
            Err(e) => {
                log::warn!("Failed to decrypt state file {name}: {e}");
                return None;
            }
        };
        match String::from_utf8(plain) {
            Ok(s) => Some(s),
            Err(e) => {
                log::warn!("State file {name} contains invalid UTF-8: {e}");
                None
            }
        }
    }

    pub fn write_state_file(&self, name: &str, content: &str) -> Result<(), SoneError> {
        let path = self.cache_dir.join(name);
        let encrypted = self.crypto.encrypt(content.as_bytes())?;
        fs::write(&path, encrypted)?;
        Ok(())
    }
}

#[cfg(test)]
mod settings_tests {
    use super::Settings;

    // Play reporting ships on. Existing configs predate the field, so the serde
    // default is what governs upgrades — not just Settings::default().
    #[test]
    fn report_plays_defaults_on() {
        assert!(Settings::default().report_plays);
        let upgraded: Settings = serde_json::from_str("{}").unwrap();
        assert!(upgraded.report_plays);
    }
}
