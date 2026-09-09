//! Playback, scrobbling, network and integration settings.
//!
//! `load` and most setters are synchronous: the underlying `utility` getters
//! only touch already-resident state (atomics, the settings file loaded once
//! at startup, or the cached audio-device list) — the same cheap-work
//! rationale `ThemeController` uses for its own synchronous invokables. Only
//! calls that hit the network or the filesystem for real (proxy apply/test,
//! scrobble auth, report-plays backlog flush) go through `runtime::spawn` +
//! `qt_thread().queue`.
//!
//! Setter invokables are named `apply_<field>` rather than `set_<field>`:
//! cxx-qt already generates a `set_<property>` Rust method (and QML WRITE)
//! for every `#[qproperty]`, so a same-named `#[qinvokable]` is a duplicate
//! definition. QML must call `apply_*` to persist a change — writing the
//! property directly only updates the in-memory value, it does not save.
//!
//! No MCP or overlay properties here yet: `Settings` (in `klang-core/src/
//! lib.rs`) already has `mcp_enabled`/`mcp_port`/`mcp_token` and
//! `overlay_enabled`/`overlay_host`/`overlay_port`, and `mcp::start_server`/
//! `overlay::start_server` use them, but `klang-core/src/api/` has no
//! getter/setter wrapping them — so there is nothing for this bridge to call
//! without reaching past the facade.

use crate::core as app;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use klang_core::api::{mcp, overlay, scrobble, utility};
use klang_core::scrobble::ProviderStatus;
use klang_core::{ProxySettings, SoneError};
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
        #[qproperty(QString, error)]
        // Playback
        #[qproperty(QString, max_quality)]
        #[qproperty(bool, volume_normalization)]
        #[qproperty(bool, gapless)]
        #[qproperty(bool, autoplay)]
        #[qproperty(bool, allow_explicit)]
        /// "auto", "en" or "de"; `Tr` resolves "auto" against the locale.
        #[qproperty(QString, language)]
        #[qproperty(bool, gapless_supported)]
        #[qproperty(bool, exclusive_mode)]
        #[qproperty(bool, bit_perfect)]
        #[qproperty(QString, exclusive_device)]
        #[qproperty(QString, audio_devices_json)]
        // Integrations
        #[qproperty(bool, discord_rpc)]
        #[qproperty(QString, discord_status_text)]
        #[qproperty(bool, report_plays)]
        // System
        #[qproperty(bool, minimize_to_tray)]
        #[qproperty(bool, enable_logging)]
        #[qproperty(QString, proxy_json)]
        #[qproperty(bool, proxy_testing)]
        #[qproperty(QString, proxy_test_result)]
        // Scrobbling
        #[qproperty(QString, scrobble_status_json)]
        #[qproperty(QString, scrobble_pending_provider)]
        #[qproperty(QString, scrobble_auth_url)]
        #[qproperty(bool, scrobble_busy)]

        /// Serialised `McpConnectionInfo` plus the token, and the matching
        /// `OverlayConnectionInfo`. Both are whole objects rather than split
        /// properties because a server's enabled/url/port only make sense
        /// together — a stale port next to a fresh url reads as a bug.
        #[qproperty(QString, mcp_json)]
        #[qproperty(QString, overlay_json)]
        type SettingsController = super::SettingsControllerRust;

        /// Populate every property from persisted/runtime state. Call once
        /// when the settings page is shown.
        #[qinvokable]
        fn load(self: Pin<&mut SettingsController>);

        #[qinvokable]
        fn apply_max_quality(self: Pin<&mut SettingsController>, quality: &QString);
        #[qinvokable]
        fn apply_volume_normalization(self: Pin<&mut SettingsController>, enabled: bool);
        #[qinvokable]
        fn apply_gapless(self: Pin<&mut SettingsController>, enabled: bool);
        #[qinvokable]
        fn apply_autoplay(self: Pin<&mut SettingsController>, enabled: bool);
        #[qinvokable]
        fn apply_language(self: Pin<&mut SettingsController>, language: &QString);
        /// Only filters what klang queues on its own — radio and autoplay.
        #[qinvokable]
        fn apply_allow_explicit(self: Pin<&mut SettingsController>, allowed: bool);
        #[qinvokable]
        fn apply_exclusive_mode(self: Pin<&mut SettingsController>, enabled: bool);
        #[qinvokable]
        fn apply_bit_perfect(self: Pin<&mut SettingsController>, enabled: bool);
        #[qinvokable]
        fn apply_exclusive_device(self: Pin<&mut SettingsController>, device: &QString);

        #[qinvokable]
        fn apply_discord_rpc(self: Pin<&mut SettingsController>, enabled: bool);
        #[qinvokable]
        fn apply_discord_status_text(self: Pin<&mut SettingsController>, text: &QString);
        #[qinvokable]
        fn apply_report_plays(self: Pin<&mut SettingsController>, enabled: bool);

        #[qinvokable]
        fn apply_minimize_to_tray(self: Pin<&mut SettingsController>, enabled: bool);
        #[qinvokable]
        fn apply_enable_logging(self: Pin<&mut SettingsController>, enabled: bool);
        #[qinvokable]
        fn open_log_folder(self: Pin<&mut SettingsController>);

        /// `json` is a serialised `ProxySettings`.
        #[qinvokable]
        fn apply_proxy_json(self: Pin<&mut SettingsController>, json: &QString);
        #[qinvokable]
        fn test_proxy(self: Pin<&mut SettingsController>, json: &QString);

        #[qinvokable]
        fn cache_stats(self: &SettingsController) -> QString;
        #[qinvokable]
        fn clear_cache(self: Pin<&mut SettingsController>);

        #[qinvokable]
        fn refresh_scrobble_status(self: Pin<&mut SettingsController>);
        #[qinvokable]
        fn connect_lastfm(self: Pin<&mut SettingsController>);
        #[qinvokable]
        fn connect_librefm(self: Pin<&mut SettingsController>);
        /// Exchange the token from a pending Last.fm/Libre.fm browser
        /// round-trip for a session. No-op if nothing is pending.
        #[qinvokable]
        fn confirm_scrobble_auth(self: Pin<&mut SettingsController>);
        #[qinvokable]
        fn connect_listenbrainz(self: Pin<&mut SettingsController>, token: &QString);
        #[qinvokable]
        fn disconnect_scrobbler(self: Pin<&mut SettingsController>, provider: &QString);

        #[qinvokable]
        fn refresh_mcp(self: Pin<&mut SettingsController>);
        #[qinvokable]
        fn apply_mcp_enabled(self: Pin<&mut SettingsController>, enabled: bool);
        #[qinvokable]
        fn regenerate_mcp_token(self: Pin<&mut SettingsController>);

        #[qinvokable]
        fn refresh_overlay(self: Pin<&mut SettingsController>);
        #[qinvokable]
        fn apply_overlay_enabled(self: Pin<&mut SettingsController>, enabled: bool);
        #[qinvokable]
        fn apply_overlay_host(self: Pin<&mut SettingsController>, host: &QString);
        #[qinvokable]
        fn apply_overlay_port(self: Pin<&mut SettingsController>, port: i32);
    }

    impl cxx_qt::Threading for SettingsController {}
}

#[derive(Default)]
pub struct SettingsControllerRust {
    error: QString,
    max_quality: QString,
    volume_normalization: bool,
    gapless: bool,
    autoplay: bool,
    allow_explicit: bool,
    language: QString,
    gapless_supported: bool,
    exclusive_mode: bool,
    bit_perfect: bool,
    exclusive_device: QString,
    audio_devices_json: QString,
    discord_rpc: bool,
    discord_status_text: QString,
    report_plays: bool,
    minimize_to_tray: bool,
    enable_logging: bool,
    proxy_json: QString,
    proxy_testing: bool,
    proxy_test_result: QString,
    scrobble_status_json: QString,
    scrobble_pending_provider: QString,
    scrobble_auth_url: QString,
    scrobble_busy: bool,
    mcp_json: QString,
    overlay_json: QString,
    /// Request token for an in-flight Last.fm/Libre.fm browser auth. Not a
    /// Q_PROPERTY: QML never needs the raw token, only whether a provider is
    /// pending confirmation.
    pending_token: String,
}

fn proxy_to_json(settings: &ProxySettings) -> String {
    serde_json::to_string(settings).unwrap_or_else(|_| "{}".to_string())
}

fn proxy_from_json(json: &str) -> Option<ProxySettings> {
    serde_json::from_str(json).ok()
}

/// Applied on the Qt thread after any scrobble call that may have changed a
/// provider's connection state. Shared by five call sites below.
fn apply_scrobble_status(
    mut obj: Pin<&mut qobject::SettingsController>,
    statuses: Result<Vec<ProviderStatus>, SoneError>,
) {
    if let Ok(list) = statuses {
        let json = serde_json::to_string(&list).unwrap_or_else(|_| "[]".to_string());
        obj.as_mut().set_scrobble_status_json(QString::from(&json));
    }
}

impl qobject::SettingsController {
    pub fn load(mut self: Pin<&mut Self>) {
        let state = app::state();

        self.as_mut()
            .set_max_quality(QString::from(&utility::get_max_quality(state)));
        self.as_mut()
            .set_volume_normalization(utility::get_volume_normalization(state));
        self.as_mut().set_gapless(utility::get_gapless(state));
        self.as_mut().set_autoplay(utility::get_autoplay(state));
        self.as_mut()
            .set_allow_explicit(utility::get_allow_explicit(state));
        self.as_mut()
            .set_language(QString::from(&utility::get_language(state)));
        self.as_mut()
            .set_gapless_supported(utility::get_gapless_supported());
        self.as_mut()
            .set_exclusive_mode(utility::get_exclusive_mode(state));
        self.as_mut().set_bit_perfect(utility::get_bit_perfect(state));
        self.as_mut().set_exclusive_device(QString::from(
            &utility::get_exclusive_device(state).unwrap_or_default(),
        ));
        match utility::list_audio_devices(state) {
            Ok(devices) => {
                let json = serde_json::to_string(&devices).unwrap_or_else(|_| "[]".to_string());
                self.as_mut().set_audio_devices_json(QString::from(&json));
            }
            Err(e) => self.as_mut().set_error(QString::from(&e.to_string())),
        }

        self.as_mut().set_discord_rpc(utility::get_discord_rpc(state));
        self.as_mut().set_discord_status_text(QString::from(
            &utility::get_discord_status_text(state),
        ));
        self.as_mut()
            .set_report_plays(utility::get_report_plays(state));

        self.as_mut()
            .set_minimize_to_tray(utility::get_minimize_to_tray(state));
        self.as_mut()
            .set_enable_logging(utility::get_enable_logging());
        self.as_mut().set_proxy_json(QString::from(&proxy_to_json(
            &utility::get_proxy_settings(state),
        )));

        self.refresh_scrobble_status();
    }

    pub fn apply_max_quality(mut self: Pin<&mut Self>, quality: &QString) {
        let quality = quality.to_string();
        match utility::set_max_quality(app::state(), quality.clone()) {
            Ok(()) => self.as_mut().set_max_quality(QString::from(&quality)),
            Err(e) => self.as_mut().set_error(QString::from(&e.to_string())),
        }
    }

    pub fn apply_volume_normalization(mut self: Pin<&mut Self>, enabled: bool) {
        match utility::set_volume_normalization(app::state(), enabled) {
            Ok(()) => self.as_mut().set_volume_normalization(enabled),
            Err(e) => self.as_mut().set_error(QString::from(&e.to_string())),
        }
    }

    pub fn apply_language(mut self: Pin<&mut Self>, language: &QString) {
        let language = language.to_string();
        match utility::set_language(app::state(), language.clone()) {
            Ok(()) => self.as_mut().set_language(QString::from(&language)),
            Err(e) => self.as_mut().set_error(QString::from(&e.to_string())),
        }
    }

    pub fn apply_autoplay(mut self: Pin<&mut Self>, enabled: bool) {
        match utility::set_autoplay(app::state(), enabled) {
            Ok(()) => self.as_mut().set_autoplay(enabled),
            Err(e) => self.as_mut().set_error(QString::from(&e.to_string())),
        }
    }

    pub fn apply_allow_explicit(mut self: Pin<&mut Self>, allowed: bool) {
        match utility::set_allow_explicit(app::state(), allowed) {
            Ok(()) => self.as_mut().set_allow_explicit(allowed),
            Err(e) => self.as_mut().set_error(QString::from(&e.to_string())),
        }
    }

    pub fn apply_gapless(mut self: Pin<&mut Self>, enabled: bool) {
        match utility::set_gapless(app::state(), enabled) {
            Ok(()) => self.as_mut().set_gapless(enabled),
            Err(e) => self.as_mut().set_error(QString::from(&e.to_string())),
        }
    }

    pub fn apply_exclusive_mode(mut self: Pin<&mut Self>, enabled: bool) {
        match utility::set_exclusive_mode(app::state(), enabled) {
            // utility.rs force-disables bit-perfect when exclusive mode goes
            // off; mirror that so the toggle reflects what actually happened.
            Ok(()) => {
                self.as_mut().set_exclusive_mode(enabled);
                if !enabled {
                    self.as_mut().set_bit_perfect(false);
                }
            }
            Err(e) => self.as_mut().set_error(QString::from(&e.to_string())),
        }
    }

    pub fn apply_bit_perfect(mut self: Pin<&mut Self>, enabled: bool) {
        match utility::set_bit_perfect(app::state(), enabled) {
            Ok(()) => {
                self.as_mut().set_bit_perfect(enabled);
                if enabled {
                    self.as_mut().set_exclusive_mode(true);
                }
            }
            Err(e) => self.as_mut().set_error(QString::from(&e.to_string())),
        }
    }

    pub fn apply_exclusive_device(mut self: Pin<&mut Self>, device: &QString) {
        let device = device.to_string();
        match utility::set_exclusive_device(app::state(), device.clone()) {
            Ok(()) => self.as_mut().set_exclusive_device(QString::from(&device)),
            Err(e) => self.as_mut().set_error(QString::from(&e.to_string())),
        }
    }

    pub fn apply_discord_rpc(mut self: Pin<&mut Self>, enabled: bool) {
        match utility::set_discord_rpc(app::state(), enabled) {
            Ok(()) => self.as_mut().set_discord_rpc(enabled),
            Err(e) => self.as_mut().set_error(QString::from(&e.to_string())),
        }
    }

    pub fn apply_discord_status_text(mut self: Pin<&mut Self>, text: &QString) {
        let text = text.to_string();
        match utility::set_discord_status_text(app::state(), text.clone()) {
            Ok(()) => self.as_mut().set_discord_status_text(QString::from(&text)),
            Err(e) => self.as_mut().set_error(QString::from(&e.to_string())),
        }
    }

    pub fn apply_report_plays(self: Pin<&mut Self>, enabled: bool) {
        let qt = self.qt_thread();
        klang_core::runtime::spawn(async move {
            let result = utility::set_report_plays(app::state(), enabled).await;
            let _ = qt.queue(move |mut obj| match result {
                Ok(()) => obj.as_mut().set_report_plays(enabled),
                Err(e) => obj.as_mut().set_error(QString::from(&e.to_string())),
            });
        });
    }

    pub fn apply_minimize_to_tray(mut self: Pin<&mut Self>, enabled: bool) {
        match utility::set_minimize_to_tray(app::state(), enabled) {
            Ok(()) => self.as_mut().set_minimize_to_tray(enabled),
            Err(e) => self.as_mut().set_error(QString::from(&e.to_string())),
        }
    }

    pub fn apply_enable_logging(mut self: Pin<&mut Self>, enabled: bool) {
        match utility::set_enable_logging(enabled) {
            Ok(()) => self.as_mut().set_enable_logging(enabled),
            Err(e) => self.as_mut().set_error(QString::from(&e.to_string())),
        }
    }

    pub fn open_log_folder(mut self: Pin<&mut Self>) {
        if let Err(e) = utility::open_log_folder() {
            self.as_mut().set_error(QString::from(&e));
        }
    }

    pub fn apply_proxy_json(mut self: Pin<&mut Self>, json: &QString) {
        let settings = match proxy_from_json(&json.to_string()) {
            Some(s) => s,
            None => {
                self.as_mut()
                    .set_error(QString::from("Invalid proxy settings"));
                return;
            }
        };
        let qt = self.qt_thread();
        klang_core::runtime::spawn(async move {
            let result = utility::set_proxy_settings(app::state(), settings.clone()).await;
            let json = proxy_to_json(&settings);
            let _ = qt.queue(move |mut obj| match result {
                Ok(()) => obj.as_mut().set_proxy_json(QString::from(&json)),
                Err(e) => obj.as_mut().set_error(QString::from(&e.to_string())),
            });
        });
    }

    pub fn test_proxy(mut self: Pin<&mut Self>, json: &QString) {
        let settings = match proxy_from_json(&json.to_string()) {
            Some(s) => s,
            None => {
                self.as_mut()
                    .set_error(QString::from("Invalid proxy settings"));
                return;
            }
        };
        self.as_mut().set_proxy_testing(true);
        self.as_mut().set_proxy_test_result(QString::from(""));
        let qt = self.qt_thread();
        klang_core::runtime::spawn(async move {
            let message = match utility::test_proxy_connection(settings).await {
                Ok(m) | Err(m) => m,
            };
            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_proxy_testing(false);
                obj.as_mut().set_proxy_test_result(QString::from(&message));
            });
        });
    }

    /// `DiskCache::stats` only reads an in-memory index (no disk I/O), so
    /// blocking briefly here is the same trade-off `ThemeController` makes.
    pub fn cache_stats(self: &Self) -> QString {
        let stats = klang_core::runtime::block_on(utility::get_cache_stats(app::state()));
        let json = match stats {
            Ok(s) => serde_json::to_string(&s).unwrap_or_else(|_| "{}".to_string()),
            Err(_) => "{}".to_string(),
        };
        QString::from(&json)
    }

    pub fn clear_cache(mut self: Pin<&mut Self>) {
        if let Err(e) = klang_core::runtime::block_on(utility::clear_disk_cache(app::state())) {
            self.as_mut().set_error(QString::from(&e.to_string()));
        }
    }

    pub fn refresh_scrobble_status(mut self: Pin<&mut Self>) {
        let statuses = klang_core::runtime::block_on(scrobble::get_scrobble_status(app::state()));
        match statuses {
            Ok(list) => {
                let json = serde_json::to_string(&list).unwrap_or_else(|_| "[]".to_string());
                self.as_mut().set_scrobble_status_json(QString::from(&json));
            }
            Err(e) => self.as_mut().set_error(QString::from(&e.to_string())),
        }
    }

    pub fn connect_lastfm(self: Pin<&mut Self>) {
        self.start_audioscrobbler_auth("lastfm");
    }

    pub fn connect_librefm(self: Pin<&mut Self>) {
        self.start_audioscrobbler_auth("librefm");
    }

    fn start_audioscrobbler_auth(mut self: Pin<&mut Self>, provider: &'static str) {
        self.as_mut().set_error(QString::from(""));
        self.as_mut().set_scrobble_busy(true);
        let qt = self.qt_thread();
        klang_core::runtime::spawn(async move {
            let result = if provider == "lastfm" {
                scrobble::connect_lastfm(app::state()).await
            } else {
                scrobble::connect_librefm(app::state()).await
            };
            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_scrobble_busy(false);
                match result {
                    Ok(resp) => {
                        obj.as_mut().rust_mut().pending_token = resp.token;
                        obj.as_mut()
                            .set_scrobble_pending_provider(QString::from(provider));
                        obj.as_mut().set_scrobble_auth_url(QString::from(&resp.url));
                    }
                    Err(e) => obj.as_mut().set_error(QString::from(&e.to_string())),
                }
            });
        });
    }

    pub fn confirm_scrobble_auth(mut self: Pin<&mut Self>) {
        let provider = self.scrobble_pending_provider().to_string();
        if provider.is_empty() {
            return;
        }
        let token = self.rust().pending_token.clone();
        self.as_mut().set_scrobble_busy(true);
        let qt = self.qt_thread();
        klang_core::runtime::spawn(async move {
            let result =
                scrobble::complete_audioscrobbler_auth(app::state(), provider, token).await;
            let statuses = scrobble::get_scrobble_status(app::state()).await;
            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_scrobble_busy(false);
                obj.as_mut().rust_mut().pending_token.clear();
                obj.as_mut().set_scrobble_pending_provider(QString::from(""));
                obj.as_mut().set_scrobble_auth_url(QString::from(""));
                if let Err(e) = result {
                    obj.as_mut().set_error(QString::from(&e.to_string()));
                }
                apply_scrobble_status(obj.as_mut(), statuses);
            });
        });
    }

    pub fn connect_listenbrainz(mut self: Pin<&mut Self>, token: &QString) {
        let token = token.to_string();
        self.as_mut().set_error(QString::from(""));
        self.as_mut().set_scrobble_busy(true);
        let qt = self.qt_thread();
        klang_core::runtime::spawn(async move {
            let result = scrobble::connect_listenbrainz(app::state(), token).await;
            let statuses = scrobble::get_scrobble_status(app::state()).await;
            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_scrobble_busy(false);
                if let Err(e) = result {
                    obj.as_mut().set_error(QString::from(&e.to_string()));
                }
                apply_scrobble_status(obj.as_mut(), statuses);
            });
        });
    }

    pub fn disconnect_scrobbler(mut self: Pin<&mut Self>, provider: &QString) {
        let provider = provider.to_string();
        self.as_mut().set_scrobble_busy(true);
        let qt = self.qt_thread();
        klang_core::runtime::spawn(async move {
            let result = scrobble::disconnect_provider(app::state(), provider).await;
            let statuses = scrobble::get_scrobble_status(app::state()).await;
            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_scrobble_busy(false);
                if let Err(e) = result {
                    obj.as_mut().set_error(QString::from(&e.to_string()));
                }
                apply_scrobble_status(obj.as_mut(), statuses);
            });
        });
    }

    pub fn refresh_mcp(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        klang_core::runtime::spawn(async move {
            let info = mcp::mcp_get_connection_info(app::state()).await;
            let token = mcp::mcp_token(app::state());
            let _ = qt.queue(move |obj| publish_mcp(obj, info, token));
        });
    }

    pub fn apply_mcp_enabled(self: Pin<&mut Self>, enabled: bool) {
        let qt = self.qt_thread();
        klang_core::runtime::spawn(async move {
            let info = mcp::mcp_set_enabled(app::state(), &app::handle(), enabled).await;
            let token = mcp::mcp_token(app::state());
            let _ = qt.queue(move |obj| publish_mcp(obj, info, token));
        });
    }

    pub fn regenerate_mcp_token(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        klang_core::runtime::spawn(async move {
            let info = mcp::mcp_regenerate_token(app::state(), &app::handle()).await;
            let token = mcp::mcp_token(app::state());
            let _ = qt.queue(move |obj| publish_mcp(obj, info, token));
        });
    }

    pub fn refresh_overlay(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        klang_core::runtime::spawn(async move {
            let info = overlay::overlay_get_connection_info(app::state()).await;
            let _ = qt.queue(move |obj| publish_overlay(obj, info));
        });
    }

    pub fn apply_overlay_enabled(self: Pin<&mut Self>, enabled: bool) {
        let qt = self.qt_thread();
        klang_core::runtime::spawn(async move {
            let info = overlay::overlay_set_enabled(app::state(), enabled).await;
            let _ = qt.queue(move |obj| publish_overlay(obj, info));
        });
    }

    pub fn apply_overlay_host(self: Pin<&mut Self>, host: &QString) {
        let host = host.to_string();
        let qt = self.qt_thread();
        klang_core::runtime::spawn(async move {
            let info = overlay::overlay_set_host(app::state(), host).await;
            let _ = qt.queue(move |obj| publish_overlay(obj, info));
        });
    }

    pub fn apply_overlay_port(self: Pin<&mut Self>, port: i32) {
        let port = port.clamp(0, u16::MAX as i32) as u16;
        let qt = self.qt_thread();
        klang_core::runtime::spawn(async move {
            let info = overlay::overlay_set_port(app::state(), port).await;
            let _ = qt.queue(move |obj| publish_overlay(obj, info));
        });
    }
}

/// Both servers report the same way: on success replace the whole info
/// object, on failure keep the last known state and surface the message, so
/// a rejected port does not blank the panel.
fn publish_mcp(
    mut obj: Pin<&mut qobject::SettingsController>,
    info: Result<mcp::McpConnectionInfo, SoneError>,
    token: String,
) {
    match info {
        Ok(info) => {
            let json = serde_json::json!({
                "enabled": info.enabled,
                "url": info.url,
                "port": info.port,
                "token": token,
            });
            obj.as_mut()
                .set_mcp_json(QString::from(&json.to_string()));
        }
        Err(e) => obj.as_mut().set_error(QString::from(&e.to_string())),
    }
}

fn publish_overlay(
    mut obj: Pin<&mut qobject::SettingsController>,
    info: Result<overlay::OverlayConnectionInfo, SoneError>,
) {
    match info {
        Ok(info) => {
            let json = serde_json::to_string(&info).unwrap_or_else(|_| "{}".into());
            obj.as_mut().set_overlay_json(QString::from(&json));
        }
        Err(e) => obj.as_mut().set_error(QString::from(&e.to_string())),
    }
}
