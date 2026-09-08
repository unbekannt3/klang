//! The plain-Rust facade the UI calls.
//!
//! Upstream exposed 177 `#[tauri::command]` functions; the bodies are the real
//! API and are kept here verbatim, with the Tauri extractors replaced by plain
//! borrows: `State<'_, AppState>` became `&AppState`, `tauri::AppHandle` became
//! [`crate::app::AppHandle`]. The Qt bridge in `klang-qt` calls into these.
//!
//! Not synced from upstream — see `scripts/sync-core.sh`.

pub mod auth;
pub mod library;
pub mod playback;
