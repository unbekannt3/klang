//! The shell-agnostic replacement for `tauri::AppHandle`.
//!
//! Upstream (sone) threads a `tauri::AppHandle` through the whole core and uses
//! it for exactly three things: emitting events to the frontend, reaching the
//! managed `AppState`, and raising the main window. `AppContext` provides those
//! three and nothing else, so the core no longer knows what draws the UI.
//!
//! The `Emitter` trait deliberately mirrors `tauri::Emitter`: same method name,
//! same `Result` return. That keeps all ~87 `.emit(...)` call sites in the core
//! byte-identical to upstream, so `scripts/sync-core.sh` can three-way merge
//! upstream fixes without hitting a conflict on every emit.

use serde::Serialize;
use std::sync::{Arc, OnceLock};

/// Receives events the core wants to hand to the UI. The Qt layer implements
/// this by queueing onto the Qt event loop via `CxxQtThread`.
pub trait EventSink: Send + Sync + 'static {
    fn emit_json(&self, event: &str, payload: serde_json::Value);
}

/// Raw Wayland handles for the main window, needed by `zwp_idle_inhibit`.
///
/// Upstream pulled these out of GDK. The shell owns both pointers and must keep
/// the window alive for as long as an inhibitor exists. Qt hands them over via
/// `QNativeInterface::QWaylandApplication` / `QWaylandWindow`.
#[derive(Clone, Copy)]
pub struct WaylandSurface {
    pub display: *mut std::ffi::c_void,
    pub surface: *mut std::ffi::c_void,
}

// The pointers are opaque handles into libwayland, which is itself thread-safe;
// the core only passes them to wayland-client, never dereferences them.
unsafe impl Send for WaylandSurface {}
unsafe impl Sync for WaylandSurface {}

/// Window actions the core occasionally needs (tray "Show", MPRIS `Raise`).
pub trait WindowShell: Send + Sync + 'static {
    /// Un-minimize, show and focus the main window.
    fn raise(&self);
    /// Hide the main window without quitting (minimize-to-tray).
    fn hide(&self);
    /// Ask the shell to quit the application.
    fn quit(&self);
    /// Wayland handles for the main window, or `None` off Wayland / before the
    /// surface exists. Must be called from the GUI thread.
    fn wayland_surface(&self) -> Option<WaylandSurface> {
        None
    }
}

/// An `EventSink` that drops everything. Useful for tests and for headless runs
/// (the MCP server and the OBS overlay work without a window).
pub struct NullSink;

impl EventSink for NullSink {
    fn emit_json(&self, event: &str, _payload: serde_json::Value) {
        log::trace!("[null-sink] dropped event {event}");
    }
}

/// A `WindowShell` for headless runs.
pub struct NullShell;

impl WindowShell for NullShell {
    fn raise(&self) {}
    fn hide(&self) {}
    fn quit(&self) {}
}

#[derive(Debug, thiserror::Error)]
#[error("could not serialize event payload: {0}")]
pub struct EmitError(#[from] serde_json::Error);

/// Mirrors `tauri::Emitter` so core call sites need no edit.
pub trait Emitter {
    fn emit<S: Serialize>(&self, event: &str, payload: S) -> Result<(), EmitError>;
}

/// What the core passes around in place of `tauri::AppHandle`.
///
/// Holds the event sink, the window shell and the shared [`AppState`]. `state`
/// is a `OnceLock` because `AppState::new` needs the handle it will be stored
/// in; [`AppContext::bootstrap`] closes that loop. The resulting reference cycle
/// keeps the context alive for the life of the process, which is what we want.
///
/// [`AppState`]: crate::AppState
pub struct AppContext {
    sink: Box<dyn EventSink>,
    window: Box<dyn WindowShell>,
    state: OnceLock<Arc<crate::AppState>>,
}

/// Drop-in for `tauri::AppHandle`: cheap to clone, shared by every subsystem.
pub type AppHandle = Arc<AppContext>;

impl AppContext {
    /// Build the context and the [`AppState`] it owns.
    ///
    /// [`AppState`]: crate::AppState
    pub fn bootstrap(sink: Box<dyn EventSink>, window: Box<dyn WindowShell>) -> AppHandle {
        let handle: AppHandle = Arc::new(AppContext {
            sink,
            window,
            state: OnceLock::new(),
        });
        let state = Arc::new(crate::AppState::new(handle.clone()));
        // Only ever set here, immediately after construction.
        let _ = handle.state.set(state);
        handle
    }

    /// A context with no UI attached — for tests and headless subsystems.
    pub fn headless() -> AppHandle {
        Self::bootstrap(Box::new(NullSink), Box::new(NullShell))
    }

    /// The shared application state. Panics if called during `AppState::new`,
    /// which is the one moment it does not exist yet.
    pub fn state(&self) -> &crate::AppState {
        self.state
            .get()
            .expect("AppState accessed before bootstrap finished")
    }

    /// Non-panicking variant, mirroring `tauri::Manager::try_state`.
    pub fn try_state(&self) -> Option<&Arc<crate::AppState>> {
        self.state.get()
    }

    pub fn window(&self) -> &dyn WindowShell {
        self.window.as_ref()
    }
}

impl Emitter for AppContext {
    fn emit<S: Serialize>(&self, event: &str, payload: S) -> Result<(), EmitError> {
        self.sink.emit_json(event, serde_json::to_value(payload)?);
        Ok(())
    }
}
