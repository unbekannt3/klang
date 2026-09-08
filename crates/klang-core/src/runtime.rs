//! Process bootstrap: the parts of upstream's `run()` that are not Tauri.
//!
//! Upstream builds a `tauri::Builder`, and its `.setup()` hook does the real
//! work: file logging, `AppState`, applying saved audio settings, wiring
//! scrobble providers, starting the MCP server, the OBS overlay and the tray.
//! All of that lives here now, driven by a Tokio runtime this module owns
//! instead of `tauri::async_runtime`.
//!
//! What deliberately did *not* move here, because it belongs to the UI shell:
//! window creation and state, single-instance handling, deep links, global
//! shortcuts, and the 177 `#[tauri::command]` wrappers.

use crate::app::{AppContext, AppHandle, EventSink, WindowShell};
use std::future::Future;
use std::path::PathBuf;
use std::sync::atomic::Ordering;
use std::sync::OnceLock;

static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();

/// The shared Tokio runtime. Replaces `tauri::async_runtime`.
///
/// Panics if called before [`KlangCore::start`], which is a programming error
/// rather than a runtime condition.
pub fn handle() -> tokio::runtime::Handle {
    RUNTIME
        .get()
        .expect("klang runtime used before KlangCore::start")
        .handle()
        .clone()
}

/// Drop-in for `tauri::async_runtime::spawn`.
pub fn spawn<F>(future: F) -> tokio::task::JoinHandle<F::Output>
where
    F: Future + Send + 'static,
    F::Output: Send + 'static,
{
    handle().spawn(future)
}

/// Drop-in for `tauri::async_runtime::block_on`.
pub fn block_on<F: Future>(future: F) -> F::Output {
    handle().block_on(future)
}

/// Where settings, cache and logs live: `$KLANG_CONFIG_DIR`, else
/// `~/.config/klang`.
///
/// klang keeps its own profile so it can run beside an existing sone install —
/// including a Flatpak one, whose profile lives under `~/.var/app/`. To start
/// from an existing sone login, copy that profile over once:
///
/// ```text
/// cp -r ~/.var/app/io.github.lullabyX.sone/config/sone ~/.config/klang
/// ```
pub fn config_dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("KLANG_CONFIG_DIR") {
        return PathBuf::from(dir);
    }
    dirs::config_dir()
        .map(|d| d.join("klang"))
        .unwrap_or_else(|| PathBuf::from("./.klang"))
}

/// Owns the runtime, the logger handle and the application context.
///
/// Keep it alive for the whole process — dropping it flushes the log file and
/// tears down every background task.
pub struct KlangCore {
    handle: AppHandle,
    _logger: flexi_logger::LoggerHandle,
}

impl KlangCore {
    /// Bring the core up. The caller supplies how events reach the UI and how
    /// the main window is controlled; [`crate::app::NullSink`] and
    /// [`crate::app::NullShell`] make this work headless.
    pub fn start(sink: Box<dyn EventSink>, window: Box<dyn WindowShell>) -> Self {
        let dir = config_dir();

        // File logging first, so anything the bootstrap logs is captured.
        // flexi_logger flushes on drop, hence the handle stored on Self.
        let logging_enabled = crate::logging::read_logging_preference(&dir.join("logging.toggle"));
        let logger = crate::logging::init_logging(dir.join("logs"), logging_enabled);

        RUNTIME.get_or_init(|| {
            tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .thread_name("klang-worker")
                .build()
                .expect("could not start Tokio runtime")
        });

        let handle = AppContext::bootstrap(sink, window);

        apply_saved_audio_mode(&handle);
        prewarm_audio_devices(&handle);
        init_scrobble_providers(&handle);
        start_background_services(&handle);

        Self {
            handle,
            _logger: logger,
        }
    }

    /// Headless core — no window, events dropped. Used by tests.
    pub fn headless() -> Self {
        Self::start(
            Box::new(crate::app::NullSink),
            Box::new(crate::app::NullShell),
        )
    }

    pub fn handle(&self) -> &AppHandle {
        &self.handle
    }

    pub fn state(&self) -> &crate::AppState {
        self.handle.state()
    }
}

/// Push the persisted exclusive / bit-perfect / gapless settings into the audio
/// thread. Without this the first playback runs in shared mode regardless of
/// what the user configured.
fn apply_saved_audio_mode(handle: &AppHandle) {
    let state = handle.state();
    let exclusive = state.exclusive_mode.load(Ordering::Relaxed);
    let bit_perfect = state.bit_perfect.load(Ordering::Relaxed);
    let device = state.exclusive_device.lock().unwrap().clone();

    if exclusive || bit_perfect {
        state.audio_player.set_exclusive_mode(exclusive, device).ok();
    }
    if bit_perfect {
        state.audio_player.set_bit_perfect(true).ok();
    }
    let _ = state
        .audio_player
        .set_gapless(state.gapless.load(Ordering::Relaxed));
}

/// The GStreamer device probe takes seconds, so fill the cache off the hot path.
fn prewarm_audio_devices(handle: &AppHandle) {
    let handle = handle.clone();
    std::thread::spawn(move || {
        if let Ok(devices) = crate::audio::list_alsa_devices() {
            *handle.state().cached_audio_devices.lock().unwrap() = Some(devices);
        }
    });
}

/// Register Last.fm, Libre.fm and ListenBrainz from saved credentials, then
/// drain whatever the last session could not submit.
fn init_scrobble_providers(handle: &AppHandle) {
    let handle = handle.clone();
    spawn(async move {
        let state = handle.state();

        if let Some(settings) = state.load_settings() {
            let http_client = crate::tidal_api::build_http_client(&settings.proxy)
                .unwrap_or_else(|_| {
                    reqwest::Client::builder()
                        .timeout(std::time::Duration::from_secs(30))
                        .build()
                        .expect("could not build fallback HTTP client")
                });

            if let Some(ref creds) = settings.scrobble.lastfm {
                if crate::embedded_lastfm::has_stream_keys() {
                    let provider = crate::scrobble::lastfm::AudioscrobblerProvider::new(
                        "lastfm",
                        "https://ws.audioscrobbler.com/2.0/",
                        "https://www.last.fm/api/auth/",
                        crate::embedded_lastfm::stream_key_a(),
                        crate::embedded_lastfm::stream_key_b(),
                        http_client.clone(),
                    );
                    provider
                        .set_session(creds.session_key.clone(), creds.username.clone())
                        .await;
                    state.scrobble_manager.add_provider(Box::new(provider)).await;
                    log::info!("Last.fm scrobbling enabled for {}", creds.username);
                }
            }

            if let Some(ref creds) = settings.scrobble.librefm {
                if crate::embedded_librefm::has_stream_keys() {
                    let provider = crate::scrobble::lastfm::AudioscrobblerProvider::new(
                        "librefm",
                        crate::scrobble::librefm::LIBREFM_API_URL,
                        "https://libre.fm/api/auth/",
                        crate::embedded_librefm::stream_key_a(),
                        crate::embedded_librefm::stream_key_b(),
                        http_client.clone(),
                    );
                    provider
                        .set_session(creds.session_key.clone(), creds.username.clone())
                        .await;
                    state.scrobble_manager.add_provider(Box::new(provider)).await;
                    log::info!("Libre.fm scrobbling enabled for {}", creds.username);
                }
            }

            if let Some(ref creds) = settings.scrobble.listenbrainz {
                let provider =
                    crate::scrobble::listenbrainz::ListenBrainzProvider::new(http_client.clone());
                provider
                    .set_token(creds.token.clone(), creds.username.clone())
                    .await;
                state.scrobble_manager.add_provider(Box::new(provider)).await;
                log::info!("ListenBrainz scrobbling enabled for {}", creds.username);
            }
        }

        state.scrobble_manager.drain_queue().await;
        state.tidal_reporter.drain_queue().await;
    });
}

/// MCP server, OBS overlay and system tray. Each checks its own setting and
/// returns immediately when disabled.
fn start_background_services(handle: &AppHandle) {
    let for_mcp = handle.clone();
    spawn(async move {
        crate::mcp::ensure_mcp_started(&for_mcp).await;
    });

    let for_overlay = handle.clone();
    spawn(async move {
        crate::overlay::ensure_overlay_started(&for_overlay).await;
    });

    #[cfg(target_os = "linux")]
    crate::tray::setup(handle);
}
