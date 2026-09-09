//! The core's side of window control.
//!
//! `WindowShell` (core.rs) can only post `"raise"` / `"hide"` / `"quit"` onto a
//! channel, because it runs before any window exists. This turns those into
//! signals on the Qt thread; `Main.qml` acts on them.

use crate::core as app;
use cxx_qt::{CxxQtType, Threading};
use std::pin::Pin;

#[cxx_qt::bridge]
pub mod qobject {
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        type WindowController = super::WindowControllerRust;

        /// Subscribe to the core's window requests. Call once.
        #[qinvokable]
        fn attach(self: Pin<&mut WindowController>);

        #[qsignal]
        fn raise_requested(self: Pin<&mut WindowController>);
        #[qsignal]
        fn hide_requested(self: Pin<&mut WindowController>);
        #[qsignal]
        fn quit_requested(self: Pin<&mut WindowController>);
    }

    impl cxx_qt::Threading for WindowController {}
}

#[derive(Default)]
pub struct WindowControllerRust {
    attached: bool,
}

impl qobject::WindowController {
    pub fn attach(mut self: Pin<&mut Self>) {
        if self.rust().attached {
            return;
        }
        self.as_mut().rust_mut().attached = true;
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let Some(sender) = app::WINDOW_REQUESTS.get() else {
                return;
            };
            let mut requests = sender.subscribe();
            while let Ok(request) = requests.recv().await {
                let _ = qt.queue(move |mut obj| match request {
                    "raise" => obj.as_mut().raise_requested(),
                    "hide" => obj.as_mut().hide_requested(),
                    "quit" => obj.as_mut().quit_requested(),
                    other => log::warn!("[window] unknown request {other}"),
                });
            }
        });
    }
}
