use std::sync::atomic::Ordering;

use super::playback::compute_norm_gain;
use crate::audio::AudioDevice;
use crate::cache::{CacheResult, CacheTier};
use crate::app::AppHandle;
use crate::AppState;
use crate::SignalPath;
use crate::SoneError;

/// Open the SONE log directory (`~/.config/sone/logs`) in the system file
/// manager, creating it if it does not exist yet.
pub fn open_log_folder() -> Result<(), String> {
    let dir = dirs::config_dir()
        .map(|d| d.join("sone").join("logs"))
        .ok_or_else(|| "could not resolve config directory".to_string())?;
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    std::process::Command::new("xdg-open")
        .arg(&dir)
        .spawn()
        .map(|_| ())
        .map_err(|e| format!("failed to launch file manager: {e}"))
}

pub fn get_signal_path(state: &AppState) -> SignalPath {
    state.signal_path.snapshot()
}

pub fn refresh_signal_path(state: &AppState) -> SignalPath {
    state.pipeline_probe.refresh();
    state.signal_path.snapshot()
}

pub async fn update_tray_tooltip(app: &AppHandle, text: String) -> Result<String, SoneError> {
    #[cfg(target_os = "linux")]
    {
        // Cloned out of the mutex so the lock is not held across the await.
        let handle = app.state().tray_handle.lock().unwrap().take();
        if let Some(handle) = handle {
            handle.update_tooltip(text).await;
            *app.state().tray_handle.lock().unwrap() = Some(handle);
            return Ok("updated".into());
        }
    }
    Ok("tray not available".into())
}

pub async fn get_image_bytes(
    state: &AppState,
    url: String,
) -> Result<Vec<u8>, SoneError> {
    log::debug!("[get_image_bytes]: url={}", url);

    match state.disk_cache.get(&url, CacheTier::Image).await {
        CacheResult::Fresh(bytes) | CacheResult::Stale(bytes) => {
            log::debug!("[get_image_bytes]: cache hit ({} bytes)", bytes.len());
            Ok(bytes)
        }
        CacheResult::Miss => {
            let http_client = state.tidal_client.lock().await.raw_client().clone();
            let res = http_client.get(&url).send().await?;
            let bytes = res.bytes().await?.to_vec();

            state
                .disk_cache
                .put(&url, &bytes, CacheTier::Image, &["image"])
                .await
                .ok();
            log::debug!(
                "[get_image_bytes]: fetched and cached {} bytes",
                bytes.len()
            );

            Ok(bytes)
        }
    }
}

pub async fn get_cache_stats(
    state: &AppState,
) -> Result<crate::cache::CacheStats, SoneError> {
    Ok(state.disk_cache.stats().await)
}

pub async fn clear_disk_cache(state: &AppState) -> Result<(), SoneError> {
    log::info!("[clear_disk_cache]: user-initiated cache clear");
    state.disk_cache.clear().await;
    Ok(())
}

pub fn get_decorations(state: &AppState) -> bool {
    state.decorations.load(Ordering::Relaxed)
}

pub fn get_minimize_to_tray(state: &AppState) -> bool {
    state.minimize_to_tray.load(Ordering::Relaxed)
}

pub fn set_minimize_to_tray(state: &AppState, enabled: bool) -> Result<(), SoneError> {
    state.minimize_to_tray.store(enabled, Ordering::Relaxed);
    let mut settings = state.load_settings().unwrap_or_default();
    settings.minimize_to_tray = enabled;
    state.save_settings(&settings)?;
    Ok(())
}

pub fn get_autoplay(state: &AppState) -> bool {
    state.load_settings().unwrap_or_default().autoplay
}

pub fn set_autoplay(state: &AppState, enabled: bool) -> Result<(), SoneError> {
    let mut settings = state.load_settings().unwrap_or_default();
    settings.autoplay = enabled;
    state.save_settings(&settings)?;
    Ok(())
}

pub fn get_allow_explicit(state: &AppState) -> bool {
    state.load_settings().unwrap_or_default().allow_explicit
}

pub fn set_allow_explicit(state: &AppState, allowed: bool) -> Result<(), SoneError> {
    let mut settings = state.load_settings().unwrap_or_default();
    settings.allow_explicit = allowed;
    state.save_settings(&settings)?;
    Ok(())
}

pub fn get_volume_normalization(state: &AppState) -> bool {
    state.volume_normalization.load(Ordering::Relaxed)
}

pub fn set_volume_normalization(
    state: &AppState,
    enabled: bool,
) -> Result<(), SoneError> {
    state.volume_normalization.store(enabled, Ordering::Relaxed);

    // Immediately apply/reset normalization on the current track
    let norm_gain = if enabled {
        let rg = f64::from_bits(state.last_replay_gain.load(Ordering::Relaxed));
        let peak = f64::from_bits(state.last_peak_amplitude.load(Ordering::Relaxed));
        let rg_opt = if rg.is_finite() { Some(rg) } else { None };
        let peak_opt = if peak.is_finite() { Some(peak) } else { None };
        compute_norm_gain(rg_opt, peak_opt)
    } else {
        1.0
    };
    state
        .audio_player
        .set_normalization_gain(norm_gain)
        .map_err(SoneError::Audio)?;
    state.signal_path.set_normalization_enabled(enabled);
    let mut settings = state.load_settings().unwrap_or_default();
    settings.volume_normalization = enabled;
    state.save_settings(&settings)?;
    Ok(())
}

pub fn get_exclusive_mode(state: &AppState) -> bool {
    state.exclusive_mode.load(Ordering::Relaxed)
}

pub fn set_exclusive_mode(state: &AppState, enabled: bool) -> Result<(), SoneError> {
    state.exclusive_mode.store(enabled, Ordering::Relaxed);

    if !enabled {
        state.bit_perfect.store(false, Ordering::Relaxed);
        state
            .audio_player
            .set_bit_perfect(false)
            .map_err(SoneError::Audio)?;
    }

    let device = state.exclusive_device.lock().unwrap().clone();
    state
        .audio_player
        .set_exclusive_mode(enabled, device)
        .map_err(SoneError::Audio)?;

    let mut settings = state.load_settings().unwrap_or_default();
    settings.exclusive_mode = enabled;
    if !enabled {
        settings.bit_perfect = false;
    }
    state.save_settings(&settings)?;
    Ok(())
}

pub fn get_bit_perfect(state: &AppState) -> bool {
    state.bit_perfect.load(Ordering::Relaxed)
}

pub fn set_bit_perfect(state: &AppState, enabled: bool) -> Result<(), SoneError> {
    state.bit_perfect.store(enabled, Ordering::Relaxed);

    if enabled && !state.exclusive_mode.load(Ordering::Relaxed) {
        state.exclusive_mode.store(true, Ordering::Relaxed);
        let device = state.exclusive_device.lock().unwrap().clone();
        state
            .audio_player
            .set_exclusive_mode(true, device)
            .map_err(SoneError::Audio)?;
    }

    state
        .audio_player
        .set_bit_perfect(enabled)
        .map_err(SoneError::Audio)?;

    let mut settings = state.load_settings().unwrap_or_default();
    settings.bit_perfect = enabled;
    if enabled {
        settings.exclusive_mode = true;
    }
    state.save_settings(&settings)?;
    Ok(())
}

pub fn get_gapless(state: &AppState) -> bool {
    state.gapless.load(Ordering::Relaxed)
}

pub fn get_gapless_supported() -> bool {
    crate::audio::gapless_supported()
}

pub fn set_gapless(state: &AppState, enabled: bool) -> Result<(), SoneError> {
    state.gapless.store(enabled, Ordering::Relaxed);
    state
        .audio_player
        .set_gapless(enabled)
        .map_err(SoneError::Audio)?;
    let mut settings = state.load_settings().unwrap_or_default();
    settings.gapless = enabled;
    state.save_settings(&settings)?;
    Ok(())
}

pub fn get_max_quality(state: &AppState) -> String {
    state.max_quality.lock().unwrap().clone()
}

pub fn set_max_quality(state: &AppState, quality: String) -> Result<(), SoneError> {
    if !matches!(quality.as_str(), "HI_RES_LOSSLESS" | "LOSSLESS" | "HIGH") {
        return Err(SoneError::Parse(format!("invalid max_quality: {quality}")));
    }
    *state.max_quality.lock().unwrap() = quality.clone();
    let mut settings = state.load_settings().unwrap_or_default();
    settings.max_quality = quality;
    state.save_settings(&settings)?;
    Ok(())
}

pub fn get_exclusive_device(state: &AppState) -> Option<String> {
    state.exclusive_device.lock().unwrap().clone()
}

pub fn set_exclusive_device(state: &AppState, device: String) -> Result<(), SoneError> {
    *state.exclusive_device.lock().unwrap() = Some(device.clone());

    let enabled = state.exclusive_mode.load(Ordering::Relaxed);
    state
        .audio_player
        .set_exclusive_mode(enabled, Some(device.clone()))
        .map_err(SoneError::Audio)?;
    let mut settings = state.load_settings().unwrap_or_default();
    settings.exclusive_device = Some(device);
    state.save_settings(&settings)?;
    Ok(())
}

pub fn list_audio_devices(state: &AppState) -> Result<Vec<AudioDevice>, SoneError> {
    // Return cached devices if available (avoids slow GStreamer DeviceMonitor probe)
    let cached = state.cached_audio_devices.lock().unwrap().clone();
    if let Some(devices) = cached {
        return Ok(devices);
    }

    // First call: probe directly (not via audio thread) and cache
    let devices = crate::audio::list_alsa_devices().map_err(SoneError::Audio)?;
    *state.cached_audio_devices.lock().unwrap() = Some(devices.clone());
    Ok(devices)
}

pub fn get_discord_rpc(state: &AppState) -> bool {
    state
        .load_settings()
        .map(|s| s.discord_rpc)
        .unwrap_or(false)
}

pub fn set_discord_rpc(state: &AppState, enabled: bool) -> Result<(), SoneError> {
    if enabled {
        state
            .discord
            .send(crate::discord::DiscordCommand::Connect);
    } else {
        state
            .discord
            .send(crate::discord::DiscordCommand::Disconnect);
    }
    let mut settings = state.load_settings().unwrap_or_default();
    settings.discord_rpc = enabled;
    state.save_settings(&settings)?;
    Ok(())
}

pub fn get_report_plays(state: &AppState) -> bool {
    state.load_settings().map(|s| s.report_plays).unwrap_or(true)
}

pub async fn set_report_plays(state: &AppState, enabled: bool) -> Result<(), SoneError> {
    // Persist first: if the write fails the caller sees an error and the
    // in-memory state still matches disk. Reversing this order can silently
    // discard a user's opt-out.
    let mut settings = state.load_settings().unwrap_or_default();
    settings.report_plays = enabled;
    state.save_settings(&settings)?;

    state.tidal_reporter.set_enabled(enabled);
    if enabled {
        // Flush any offline backlog now that reporting is on.
        state.tidal_reporter.drain_queue().await;
    } else {
        // Drop the in-flight session: every lifecycle hook is gated on
        // `enabled`, so an orphaned session would keep accruing wall-clock time
        // and get reported on the next enable.
        state.tidal_reporter.clear_session().await;
    }
    Ok(())
}

pub fn get_discord_status_text(state: &AppState) -> String {
    state
        .load_settings()
        .map(|s| s.discord_status_text)
        .unwrap_or_default()
}

pub fn set_discord_status_text(state: &AppState, text: String) -> Result<(), SoneError> {
    state
        .discord
        .send(crate::discord::DiscordCommand::SetStatusText { text: text.clone() });

    let mut settings = state.load_settings().unwrap_or_default();
    settings.discord_status_text = text;
    state.save_settings(&settings)?;
    Ok(())
}

pub fn get_proxy_settings(state: &AppState) -> crate::ProxySettings {
    state
        .load_settings()
        .map(|s| s.proxy)
        .unwrap_or_default()
}

pub async fn set_proxy_settings(
    state: &AppState,
    settings: crate::ProxySettings,
) -> Result<(), SoneError> {
    // Rebuild the HTTP client with new proxy config
    {
        let mut client = state.tidal_client.lock().await;
        client.rebuild_client(&settings);
    }

    // Also rebuild scrobble provider HTTP clients
    let new_client = {
        let client = state.tidal_client.lock().await;
        client.raw_client().clone()
    };
    state
        .scrobble_manager
        .update_http_client(new_client.clone())
        .await;
    state.tidal_reporter.update_http_client(new_client);

    // Save to disk
    let mut app_settings = state.load_settings().unwrap_or_default();
    app_settings.proxy = settings;
    state.save_settings(&app_settings)?;
    Ok(())
}

pub async fn inhibit_idle(app: &AppHandle) -> Result<(), SoneError> {
    app.state().idle_inhibitor.lock().await.inhibit(app).await;
    Ok(())
}

pub async fn uninhibit_idle(state: &AppState) -> Result<(), SoneError> {
    state.idle_inhibitor.lock().await.uninhibit().await;
    Ok(())
}

pub async fn test_proxy_connection(
    settings: crate::ProxySettings,
) -> Result<String, String> {
    let client = crate::tidal_api::build_http_client(&settings)
        .map_err(|e| format!("Failed to create client: {e}"))?;

    match client
        .get("https://api.tidal.com/v1/ping")
        .timeout(std::time::Duration::from_secs(10))
        .send()
        .await
    {
        Ok(resp) => {
            let status = resp.status();
            if status.is_success() || status.as_u16() == 404 || status.as_u16() == 401 {
                Ok("Connection successful".to_string())
            } else {
                Ok(format!("Tidal responded with status {status}"))
            }
        }
        Err(e) => Err(format!("Connection failed: {e}")),
    }
}

fn logging_toggle_path() -> Option<std::path::PathBuf> {
    dirs::config_dir().map(|d| d.join("sone").join("logging.toggle"))
}

pub fn get_enable_logging() -> bool {
    let Some(path) = logging_toggle_path() else {
        return true;
    };
    let Ok(text) = std::fs::read_to_string(&path) else {
        return true;
    };
    match text.trim() {
        "false" => false,
        _ => true,
    }
}

pub fn set_enable_logging(enabled: bool) -> Result<(), SoneError> {
    let Some(path) = logging_toggle_path() else {
        return Err(SoneError::Io("Could not resolve config dir".into()));
    };
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|e| SoneError::Io(format!("Failed to create config dir: {e}")))?;
    }
    let body = if enabled { "true" } else { "false" };
    std::fs::write(&path, body)
        .map_err(|e| SoneError::Io(format!("Failed to write logging toggle: {e}")))?;
    Ok(())
}
