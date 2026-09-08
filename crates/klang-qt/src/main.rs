//! klang — a KDE-native TIDAL client.
//!
//! `main` starts the core, then hands control to Qt. Everything the UI touches
//! goes through the QObjects in `bridge`.

mod bridge;
mod core;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QString, QUrl};

fn main() {
    // Without this Qt sends its warnings to the journal whenever it decides
    // stderr is not a console, and a broken QML binding fails in total silence.
    // SAFETY: single-threaded, before any Qt or Tokio thread exists.
    unsafe {
        std::env::set_var("QT_FORCE_STDERR_LOGGING", "1");
        std::env::set_var("QT_ASSUME_STDERR_HAS_CONSOLE", "1");
    }

    // The core owns the Tokio runtime and every background service, so it has
    // to be up before QML constructs a controller that talks to it.
    crate::core::start();
    log::info!("klang core started");

    let mut app = QGuiApplication::new();
    let mut engine = QQmlApplicationEngine::new();

    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from(&QString::from(
            "qrc:/qt/qml/me/unbk/klang/qml/Main.qml",
        )));
    }

    if let Some(app) = app.as_mut() {
        app.exec();
    }
}
