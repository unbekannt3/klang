//! Phase-0 proof: boot the core with no UI attached and report what it found.
//!
//!     cargo run -p klang-core --example smoke
//!
//! Uses the real `~/.config/sone` profile, so it will pick up an existing sone
//! login. It starts the same background services the app does (MCP server, OBS
//! overlay, tray) when they are enabled in settings.

use klang_core::app::{EventSink, NullShell};
use klang_core::KlangCore;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

/// Counts events instead of dropping them, so the run shows the sink is wired.
struct CountingSink(Arc<AtomicUsize>);

impl EventSink for CountingSink {
    fn emit_json(&self, event: &str, payload: serde_json::Value) {
        self.0.fetch_add(1, Ordering::Relaxed);
        println!("  event  {event}  {payload}");
    }
}

fn main() {
    let seen = Arc::new(AtomicUsize::new(0));
    let core = KlangCore::start(Box::new(CountingSink(seen.clone())), Box::new(NullShell));
    let state = core.state();

    println!("config dir     {}", klang_core::runtime::config_dir().display());
    println!("settings       {}", state.settings_path.display());
    println!("cache          {}", state.cache_dir.display());

    match state.load_settings() {
        Some(s) => {
            println!("logged in      {}", s.auth_tokens.is_some());
            println!("max quality    {}", s.max_quality);
            println!("bit perfect    {}", s.bit_perfect);
            println!("scrobblers     lastfm={} librefm={} listenbrainz={}",
                s.scrobble.lastfm.is_some(),
                s.scrobble.librefm.is_some(),
                s.scrobble.listenbrainz.is_some());
        }
        None => println!("settings       none yet (fresh profile)"),
    }

    // The device probe runs on a background thread; give it a moment.
    std::thread::sleep(std::time::Duration::from_secs(3));
    match state.cached_audio_devices.lock().unwrap().as_ref() {
        Some(devices) => {
            println!("alsa devices   {}", devices.len());
            for d in devices.iter().take(5) {
                println!("  {d:?}");
            }
        }
        None => println!("alsa devices   probe still running"),
    }

    println!("events seen    {}", seen.load(Ordering::Relaxed));
    println!("\ncore booted without tauri.");
}
