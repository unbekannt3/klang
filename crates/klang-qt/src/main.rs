//! klang — a KDE-native TIDAL client.
//!
//! `main` starts the core, then hands control to Qt. Everything the UI touches
//! goes through the QObjects in `bridge`.

mod bridge;
mod core;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QString, QUrl};

fn main() {
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
