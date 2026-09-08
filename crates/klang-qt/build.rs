use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};

fn main() {
    // Paths are used verbatim as the Qt resource alias, so a "../" here would
    // produce an unreachable qrc URL and a window that never appears.
    CxxQtBuilder::new_qml_module(
        QmlModule::new("me.unbk.klang").qml_files([
            QmlFile::from("qml/Theme.qml").singleton(true),
            QmlFile::from("qml/Format.qml").singleton(true),
            QmlFile::from("qml/Main.qml"),
            QmlFile::from("qml/LoginPage.qml"),
            QmlFile::from("qml/FavoritesPage.qml"),
            QmlFile::from("qml/PlayerBar.qml"),
            QmlFile::from("qml/Sidebar.qml"),
            QmlFile::from("qml/TrackList.qml"),
            QmlFile::from("qml/ProgressSlider.qml"),
            QmlFile::from("qml/TitleBar.qml"),
            QmlFile::from("qml/ResizeEdges.qml"),
            QmlFile::from("qml/ThemedScrollBar.qml"),
            QmlFile::from("qml/WheelScroller.qml"),
            QmlFile::from("qml/CoverArt.qml"),
        ]),
    )
    .qrc("qml/resources.qrc")
    .qt_module("Network")
    .files([
        "src/bridge/auth.rs",
        "src/bridge/catalog.rs",
        "src/bridge/home.rs",
        "src/bridge/library.rs",
        "src/bridge/player.rs",
        "src/bridge/playlists.rs",
        "src/bridge/search.rs",
        "src/bridge/theme.rs",
    ])
    .build();
}
