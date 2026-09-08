use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(
        QmlModule::new("me.unbk.klang").qml_file("qml/Main.qml"),
    )
    .qt_module("Network")
    .files([
        "src/bridge/auth.rs",
        "src/bridge/library.rs",
        "src/bridge/player.rs",
    ])
    .build();
}
