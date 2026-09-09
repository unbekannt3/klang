//! Process-wide access to the running [`KlangCore`], plus the two shell traits
//! it needs from the UI.
//!
//! The core is started once in `main` and lives for the whole process, so the
//! QObjects reach it through a `OnceLock` rather than each carrying a handle.
//! Events the core emits are fanned out on a broadcast channel; each controller
//! subscribes and forwards what it cares about onto the Qt thread.

use klang_core::app::{EventSink, WindowShell};
use klang_core::KlangCore;
use std::sync::OnceLock;
use tokio::sync::broadcast;

static CORE: OnceLock<KlangCore> = OnceLock::new();
static EVENTS: OnceLock<broadcast::Sender<CoreEvent>> = OnceLock::new();

/// One event as the core emitted it.
#[derive(Clone, Debug)]
pub struct CoreEvent {
    pub name: String,
    pub payload: serde_json::Value,
}

/// Fans core events out to every subscribed controller. Sends are non-blocking
/// and drop when nobody listens, which is the right behaviour for UI updates.
struct BroadcastSink;

impl EventSink for BroadcastSink {
    fn emit_json(&self, event: &str, payload: serde_json::Value) {
        if let Some(tx) = EVENTS.get() {
            // Err means no subscribers — not a problem, the UI simply isn't
            // interested in this event yet.
            let _ = tx.send(CoreEvent {
                name: event.to_string(),
                payload,
            });
        }
    }
}

/// Window control. Raising and hiding need the QML window, which does not exist
/// when the core starts, so all three are routed through [`WINDOW_REQUESTS`]
/// and turned into signals by `bridge::window`.
struct QtShell;

/// Requests from the core to the window: `"raise"`, `"hide"` or `"quit"`.
pub static WINDOW_REQUESTS: OnceLock<broadcast::Sender<&'static str>> = OnceLock::new();

impl WindowShell for QtShell {
    fn raise(&self) {
        request_window("raise");
    }

    fn hide(&self) {
        request_window("hide");
    }

    fn quit(&self) {
        request_window("quit");
    }
}

fn request_window(what: &'static str) {
    if let Some(tx) = WINDOW_REQUESTS.get() {
        let _ = tx.send(what);
    }
}

/// Start the core. Call once, from `main`, before any QObject is constructed.
pub fn start() -> &'static KlangCore {
    let (tx, _) = broadcast::channel(256);
    let _ = EVENTS.set(tx);
    let (wtx, _) = broadcast::channel(16);
    let _ = WINDOW_REQUESTS.set(wtx);

    CORE.get_or_init(|| KlangCore::start(Box::new(BroadcastSink), Box::new(QtShell)))
}

/// The running core. Panics if called before [`start`], which would be a
/// construction-order bug rather than a runtime condition.
pub fn core() -> &'static KlangCore {
    CORE.get().expect("core() before core::start()")
}

pub fn state() -> &'static klang_core::AppState {
    core().state()
}

pub fn handle() -> &'static klang_core::AppHandle {
    core().handle()
}

/// Subscribe to core events. Late subscribers miss earlier events, which is
/// fine — controllers read current state on construction.
pub fn subscribe() -> broadcast::Receiver<CoreEvent> {
    EVENTS
        .get()
        .expect("subscribe() before core::start()")
        .subscribe()
}
