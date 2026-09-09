//! The cxx-qt QObjects QML binds to, plus the helpers they share.

pub mod auth;
pub mod catalog;
pub mod favorites;
pub mod feed;
pub mod home;
pub mod library;
pub mod media_row;
pub mod mix;
pub mod nowplaying;
pub mod playlists;
pub mod player;
pub mod profile;
pub mod search;
pub mod settings;
pub mod signalpath;
pub mod theme;
pub mod video;
pub mod viewall;

/// Guards a loader against a response that arrives after a newer request.
///
/// A controller keeps one of these per independent load and takes a token
/// before spawning; the token moves into the closure `CxxQtThread::queue`
/// runs back on the Qt thread, which applies the result only while the token
/// is still current:
///
/// ```ignore
/// let token = self.as_mut().rust_mut().requests.start();
/// // ... spawn, await, then on the Qt thread:
/// if !obj.rust().requests.is_current(token) {
///     return;
/// }
/// ```
///
/// Starting a request invalidates every token handed out before it, so the
/// slow answer to an abandoned query can never overwrite the fresh one.
#[derive(Default)]
pub struct RequestSeq(u64);

/// What one [`RequestSeq::start`] hands out. Copy so it can be captured by a
/// `move` closure without borrowing the controller.
#[derive(Clone, Copy, PartialEq, Eq)]
pub struct RequestToken(u64);

impl RequestSeq {
    /// Begin a request, superseding every one started before it.
    pub fn start(&mut self) -> RequestToken {
        self.0 = self.0.wrapping_add(1);
        RequestToken(self.0)
    }

    /// Whether `token` still belongs to the newest request.
    pub fn is_current(&self, token: RequestToken) -> bool {
        self.0 == token.0
    }

    /// Drop every in-flight request without starting one — for a close or
    /// clear, where the answer to what was asked is no longer wanted at all.
    pub fn cancel(&mut self) {
        self.0 = self.0.wrapping_add(1);
    }
}
