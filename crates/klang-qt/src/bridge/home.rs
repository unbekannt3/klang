//! Home, as carousel sections.
//!
//! The item flattening lives in `bridge/media_row.rs`, shared with the
//! view-all pages.

use crate::bridge::media_row::sections_to_json;
use crate::bridge::RequestSeq;
use crate::core as app;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use klang_core::api::pages;
use klang_core::tidal_api::HomePageSection;
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
        #[qproperty(bool, loading)]
        #[qproperty(QString, error)]
        #[qproperty(QString, sections_json)]
        type HomeController = super::HomeControllerRust;

        /// A JSON array of `{title, kind, items}` carousels, in TIDAL's order.
        #[qinvokable]
        fn load_home(self: Pin<&mut HomeController>);
    }

    impl cxx_qt::Threading for HomeController {}
}

#[derive(Default)]
pub struct HomeControllerRust {
    loading: bool,
    error: QString,
    sections_json: QString,
    requests: RequestSeq,
}

/// `pages::get_home_page` returns `HomePageCached { home, is_stale }` with
/// private fields (only the type itself is `pub`) — there's no accessor, and
/// adding one is out of scope here (klang-core is off-limits for this
/// change). It still derives `Serialize`, which isn't subject to Rust's field
/// privacy, so round-tripping through `serde_json::Value` is the way to reach
/// `.home` from outside the defining module.
fn sections_from_cached(cached: &pages::HomePageCached) -> Vec<HomePageSection> {
    serde_json::to_value(cached)
        .ok()
        .and_then(|v| v.get("home").and_then(|h| h.get("sections")).cloned())
        .and_then(|s| serde_json::from_value(s).ok())
        .unwrap_or_default()
}

impl qobject::HomeController {
    pub fn load_home(mut self: Pin<&mut Self>) {
        let token = self.as_mut().rust_mut().requests.start();
        self.as_mut().set_loading(true);
        self.as_mut().set_error(QString::from(""));
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let result = pages::get_home_page(app::state(), app::handle(), None).await;

            let _ = qt.queue(move |mut obj| {
                if !obj.rust().requests.is_current(token) {
                    return;
                }
                obj.as_mut().set_loading(false);
                match result {
                    Ok(cached) => {
                        let sections = sections_from_cached(&cached);
                        obj.as_mut()
                            .set_sections_json(QString::from(&sections_to_json(&sections)));
                    }
                    Err(e) => {
                        obj.as_mut().set_sections_json(QString::from("[]"));
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }
            });
        });
    }
}
