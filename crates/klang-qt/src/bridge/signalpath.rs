//! Read-only view of `klang_core::SignalPath` for the transparency panel.
//! `path_json` mirrors the whole struct (camelCase, via serde) rather than a
//! hand-picked subset, so the panel can read any field without a bridge
//! round-trip for each one.

use crate::core as app;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use klang_core::api::utility;
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
        #[qproperty(QString, path_json)]
        type SignalPathController = super::SignalPathControllerRust;

        /// Fetch the current snapshot and subscribe to `signal-path-changed`.
        /// Call once.
        #[qinvokable]
        fn attach(self: Pin<&mut SignalPathController>);

        /// Re-probe ALSA/pactl ground truth and publish the result. Cheap
        /// (a few /proc reads plus one pactl call) but still worth keeping
        /// off the constructor — only the panel that shows this needs it.
        #[qinvokable]
        fn refresh(self: Pin<&mut SignalPathController>);
    }

    impl cxx_qt::Threading for SignalPathController {}
}

#[derive(Default)]
pub struct SignalPathControllerRust {
    path_json: QString,
    attached: bool,
}

fn to_json(path: &klang_core::SignalPath) -> QString {
    QString::from(&serde_json::to_string(path).unwrap_or_else(|_| "{}".to_string()))
}

impl qobject::SignalPathController {
    pub fn attach(mut self: Pin<&mut Self>) {
        if self.rust().attached {
            return;
        }
        self.as_mut().rust_mut().attached = true;
        self.as_mut()
            .set_path_json(to_json(&utility::get_signal_path(app::state())));

        let qt = self.qt_thread();
        klang_core::runtime::spawn(async move {
            let mut events = app::subscribe();
            while let Ok(event) = events.recv().await {
                if event.name != "signal-path-changed" {
                    continue;
                }
                let json = event.payload.to_string();
                let _ = qt.queue(move |mut obj| {
                    obj.as_mut().set_path_json(QString::from(&json));
                });
            }
        });
    }

    pub fn refresh(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        klang_core::runtime::spawn(async move {
            let json = serde_json::to_string(&utility::refresh_signal_path(app::state()))
                .unwrap_or_else(|_| "{}".to_string());
            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_path_json(QString::from(&json));
            });
        });
    }
}
