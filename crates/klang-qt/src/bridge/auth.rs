//! Login state and the TIDAL device-code flow.
//!
//! The device flow is the one that needs no web engine: TIDAL hands back a
//! short code, the user types it on link.tidal.com in their own browser, and we
//! poll until the token arrives.

use crate::core as app;
use std::pin::Pin;
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use klang_core::api::auth;

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
        type AuthController = super::AuthControllerRust;

        /// Restore a saved session. Call once when the UI comes up.
        #[qinvokable]
        fn restore(self: Pin<&mut AuthController>);

        /// Ask TIDAL for a device code and start polling for the token.
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
                        obj.as_mut().set_logged_in(true);
                        obj.as_mut().set_user_id(user_id.unwrap_or(0) as i64);
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
