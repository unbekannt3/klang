//! The card that pops up when the cursor rests on an artist's name.
//!
//! Its own controller rather than a second use of CatalogController: the card
//! appears over whatever page is open, including the artist page itself, and
//! must not disturb what that page is showing.

use crate::bridge::RequestSeq;
use crate::core as app;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use klang_core::api::pages;
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
        #[qproperty(i64, artist_id)]
        #[qproperty(QString, name)]
        #[qproperty(QString, picture)]
        #[qproperty(QString, bio)]
        type ArtistCardController = super::ArtistCardControllerRust;

        /// Fetch one artist. Repeat calls for the artist already shown are
        /// free, which is what makes this cheap to drive from hover.
        #[qinvokable]
        fn load(self: Pin<&mut ArtistCardController>, artist_id: i64);
    }

    impl cxx_qt::Threading for ArtistCardController {}
}

#[derive(Default)]
pub struct ArtistCardControllerRust {
    loading: bool,
    artist_id: i64,
    name: QString,
    picture: QString,
    bio: QString,
    requests: RequestSeq,
}

impl qobject::ArtistCardController {
    pub fn load(mut self: Pin<&mut Self>, artist_id: i64) {
        if artist_id <= 0 || artist_id == *self.artist_id() {
            return;
        }
        let token = self.as_mut().rust_mut().requests.start();
        self.as_mut().set_artist_id(artist_id);
        self.as_mut().set_loading(true);
        self.as_mut().set_name(QString::default());
        self.as_mut().set_picture(QString::default());
        self.as_mut().set_bio(QString::default());
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let id = artist_id as u64;
            let (detail, bio) = tokio::join!(
                pages::get_artist_detail(app::state(), id),
                pages::get_artist_bio(app::state(), app::handle(), id),
            );

            let _ = qt.queue(move |mut obj| {
                if !obj.rust().requests.is_current(token) {
                    return;
                }
                obj.as_mut().set_loading(false);
                // Not every artist has a bio, and a card without one is still
                // worth showing, so a failure here is silent.
                obj.as_mut()
                    .set_bio(QString::from(&bio.unwrap_or_default()));
                match detail {
                    Ok(detail) => {
                        obj.as_mut().set_name(QString::from(&detail.name));
                        obj.as_mut().set_picture(QString::from(
                            &detail.picture.clone().unwrap_or_default(),
                        ));
                    }
                    Err(e) => log::warn!("[artist-card] {artist_id}: {e}"),
                }
            });
        });
    }
}
