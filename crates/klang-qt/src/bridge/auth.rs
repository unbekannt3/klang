//! Login state and the two TIDAL sign-in flows.
//!
//! PKCE is the default because TIDAL's device-code client is restricted: its
//! tokens do not grant lossless or Hi-Res, whatever the account is paying for.
//! Upstream nags device-code users to re-authenticate for exactly this reason.
//!
//! Neither flow needs a web engine. PKCE opens the user's own browser and takes
//! the redirect URL back; device-code shows a short code to type on
//! link.tidal.com.

use crate::core as app;
use std::pin::Pin;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use klang_core::api::auth;
use std::process::Command;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(bool, logged_in)]
        #[qproperty(bool, busy)]
        #[qproperty(QString, user_code)]
        #[qproperty(QString, verification_uri)]
        #[qproperty(QString, error)]
        #[qproperty(i64, user_id)]
        /// Set once the browser is open and klang is waiting for the redirect.
        #[qproperty(bool, awaiting_redirect)]
        type AuthController = super::AuthControllerRust;

        /// Restore a saved session. Call once when the UI comes up.
        #[qinvokable]
        fn restore(self: Pin<&mut AuthController>);

        /// Open the browser for PKCE sign-in. The user pastes the redirect URL
        /// into `finish_browser_login`.
        #[qinvokable]
        fn start_browser_login(self: Pin<&mut AuthController>);

        /// Complete PKCE from the URL the browser was redirected to.
        #[qinvokable]
        fn finish_browser_login(self: Pin<&mut AuthController>, redirect_url: &QString);

        /// Fall back to the device-code flow. Costs lossless quality.
        #[qinvokable]
        fn start_login(self: Pin<&mut AuthController>);

        /// Drop the session and stop playback.
        #[qinvokable]
        fn logout(self: Pin<&mut AuthController>);
    }

    impl cxx_qt::Threading for AuthController {}
}

#[derive(Default)]
pub struct AuthControllerRust {
    logged_in: bool,
    busy: bool,
    user_code: QString,
    verification_uri: QString,
    error: QString,
    user_id: i64,
    awaiting_redirect: bool,
    /// Parked between opening the browser and the redirect coming back.
    pending: Option<(String, String)>,
}

/// Pull the authorization code out of the pasted redirect URL, or accept a bare
/// code — the browser sometimes shows only that.
fn authorization_code(input: &str) -> Option<String> {
    let input = input.trim();
    if input.is_empty() {
        return None;
    }
    if let Some(query) = input.split_once('?').map(|(_, q)| q) {
        for pair in query.split('&') {
            if let Some(value) = pair.strip_prefix("code=") {
                let value = value.split('#').next().unwrap_or(value);
                if !value.is_empty() {
                    return Some(value.to_string());
                }
            }
        }
    }
    if !input.contains(' ') && !input.contains('/') && input.len() > 10 {
        return Some(input.to_string());
    }
    None
}

impl qobject::AuthController {
    pub fn restore(mut self: Pin<&mut Self>) {
        self.as_mut().set_busy(true);
        self.as_mut().set_error(QString::from(""));
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let restored = auth::load_saved_auth(app::state()).await;
            let user_id = match &restored {
                Ok(Some(_)) => auth::get_session_user_id(app::state()).await.ok(),
                _ => None,
            };

            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_busy(false);
                match restored {
                    Ok(Some(_)) => {
                        // user_id first: QML reacts to logged_in, and the
                        // handler needs the id to be there already.
                        obj.as_mut().set_user_id(user_id.unwrap_or(0) as i64);
                        obj.as_mut().set_logged_in(true);
                    }
                    Ok(None) => obj.as_mut().set_logged_in(false),
                    Err(e) => {
                        obj.as_mut().set_logged_in(false);
                        obj.as_mut().set_error(QString::from(&e.to_string()));
                    }
                }
            });
        });
    }

pub fn start_browser_login(mut self: Pin<&mut Self>) {
        self.as_mut().set_error(QString::from(""));
        let params = match auth::start_pkce_browser_login() {
            Ok(p) => p,
            Err(e) => {
                self.set_error(QString::from(&e.to_string()));
                return;
            }
        };

        if let Err(e) = open_in_browser(&params.authorize_url) {
            // Not fatal: the URL is still shown so it can be opened by hand.
            log::warn!("could not open a browser: {e}");
        }

        self.as_mut()
            .set_verification_uri(QString::from(&params.authorize_url));
        self.as_mut().set_awaiting_redirect(true);
        self.as_mut().rust_mut().pending =
            Some((params.code_verifier, params.client_unique_key));
    }

    pub fn finish_browser_login(mut self: Pin<&mut Self>, redirect_url: &QString) {
        let Some((verifier, unique_key)) = self.rust().pending.clone() else {
            self.set_error(QString::from("Start the sign-in first."));
            return;
        };
        let Some(code) = authorization_code(&redirect_url.to_string()) else {
            self.set_error(QString::from(
                "No authorization code in that URL. Paste the whole address the browser ended on.",
            ));
            return;
        };

        self.as_mut().set_busy(true);
        self.as_mut().set_error(QString::from(""));
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let result =
                auth::complete_pkce_browser_login(app::handle(), code, verifier, unique_key).await;
            let user_id = match &result {
                Ok(_) => auth::get_session_user_id(app::state()).await.unwrap_or(0),
                Err(_) => 0,
            };

            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_busy(false);
                match result {
                    Ok(_) => {
                        obj.as_mut().rust_mut().pending = None;
                        obj.as_mut().set_awaiting_redirect(false);
                        obj.as_mut().set_verification_uri(QString::from(""));
                        obj.as_mut().set_user_id(user_id as i64);
                        obj.as_mut().set_logged_in(true);
                    }
                    Err(e) => obj.as_mut().set_error(QString::from(&e.to_string())),
                }
            });
        });
    }

    pub fn start_login(mut self: Pin<&mut Self>) {
        self.as_mut().set_busy(true);
        self.as_mut().set_error(QString::from(""));
        self.as_mut().set_user_code(QString::from(""));
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let (client_id, client_secret) = match auth::get_default_credentials() {
                Ok(pair) if !pair.0.is_empty() => pair,
                _ => {
                    let _ = qt.queue(|mut obj| {
                        obj.as_mut().set_busy(false);
                        obj.as_mut().set_error(QString::from(
                            "This build has no embedded TIDAL credentials.",
                        ));
                    });
                    return;
                }
            };

            let device = match auth::start_device_auth(
                app::state(),
                client_id.clone(),
                client_secret.clone(),
            )
            .await
            {
                Ok(d) => d,
                Err(e) => {
                    let msg = e.to_string();
                    let _ = qt.queue(move |mut obj| {
                        obj.as_mut().set_busy(false);
                        obj.as_mut().set_error(QString::from(&msg));
                    });
                    return;
                }
            };

            // Show the code immediately; the user needs it before we poll.
            let code = device.user_code.clone();
            let uri = device
                .verification_uri_complete
                .clone()
                .unwrap_or_else(|| device.verification_uri.clone());
            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_user_code(QString::from(&code));
                obj.as_mut().set_verification_uri(QString::from(&uri));
            });

            let deadline =
                std::time::Instant::now() + std::time::Duration::from_secs(device.expires_in);
            let interval = std::time::Duration::from_secs(device.interval.max(1));

            loop {
                if std::time::Instant::now() >= deadline {
                    let _ = qt.queue(|mut obj| {
                        obj.as_mut().set_busy(false);
                        obj.as_mut().set_user_code(QString::from(""));
                        obj.as_mut()
                            .set_error(QString::from("The login code expired. Try again."));
                    });
                    return;
                }
                tokio::time::sleep(interval).await;

                match auth::poll_device_auth(
                    app::state(),
                    app::handle(),
                    device.device_code.clone(),
                    client_id.clone(),
                    client_secret.clone(),
                )
                .await
                {
                    // Still waiting for the user to enter the code.
                    Ok(None) => continue,
                    Ok(Some(_)) => {
                        let user_id = auth::get_session_user_id(app::state()).await.unwrap_or(0);
                        let _ = qt.queue(move |mut obj| {
                            obj.as_mut().set_busy(false);
                            obj.as_mut().set_user_code(QString::from(""));
                            obj.as_mut().set_user_id(user_id as i64);
                            obj.as_mut().set_logged_in(true);
                        });
                        return;
                    }
                    Err(e) => {
                        let msg = e.to_string();
                        let _ = qt.queue(move |mut obj| {
                            obj.as_mut().set_busy(false);
                            obj.as_mut().set_user_code(QString::from(""));
                            obj.as_mut().set_error(QString::from(&msg));
                        });
                        return;
                    }
                }
            }
        });
    }

    pub fn logout(mut self: Pin<&mut Self>) {
        self.as_mut().set_busy(true);
        let qt = self.qt_thread();

        klang_core::runtime::spawn(async move {
            let result = auth::logout(app::state()).await;
            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_busy(false);
                obj.as_mut().set_logged_in(false);
                obj.as_mut().set_user_id(0);
                if let Err(e) = result {
                    obj.as_mut().set_error(QString::from(&e.to_string()));
                }
            });
        });
    }
}

/// Hand a URL to the desktop's default browser.
fn open_in_browser(url: &str) -> std::io::Result<()> {
    Command::new("xdg-open").arg(url).spawn().map(|_| ())
}
