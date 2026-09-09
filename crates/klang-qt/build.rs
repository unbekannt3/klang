use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};

fn main() {
    // cxx-qt-build only tells cargo to watch the .rs bridges and the qrc, so
    // a QML-only edit silently kept the previous binary — every screenshot
    // after one showed the old UI.
    for entry in std::fs::read_dir("qml").expect("qml directory") {
        let path = entry.expect("qml entry").path();
        println!("cargo::rerun-if-changed={}", path.display());
    }

    // Paths are used verbatim as the Qt resource alias, so a "../" here would
    // produce an unreachable qrc URL and a window that never appears.
    CxxQtBuilder::new_qml_module(
        QmlModule::new("me.unbk.klang").qml_files([
            QmlFile::from("qml/Theme.qml").singleton(true),
            QmlFile::from("qml/Format.qml").singleton(true),
            QmlFile::from("qml/MediaRoute.qml").singleton(true),
            QmlFile::from("qml/ScrollStore.qml").singleton(true),
            QmlFile::from("qml/Tr.qml").singleton(true),
            QmlFile::from("qml/TranslationsDe.qml").singleton(true),
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
            QmlFile::from("qml/Icon.qml"),
            QmlFile::from("qml/CoverArt.qml"),
            QmlFile::from("qml/MediaCard.qml"),
            QmlFile::from("qml/ModalShield.qml"),
            QmlFile::from("qml/NamePrompt.qml"),
            QmlFile::from("qml/CoverWash.qml"),
            QmlFile::from("qml/Glass.qml"),
            QmlFile::from("qml/ArtistHoverCard.qml"),
            QmlFile::from("qml/ArtistPeek.qml").singleton(true),
            QmlFile::from("qml/OverlayStack.qml").singleton(true),
            QmlFile::from("qml/CardCarousel.qml"),
            QmlFile::from("qml/SectionList.qml"),
            QmlFile::from("qml/ThemePicker.qml"),
            QmlFile::from("qml/SettingsPage.qml"),
            QmlFile::from("qml/NowPlayingView.qml"),
            QmlFile::from("qml/ContextMenu.qml"),
            QmlFile::from("qml/TrackContextMenu.qml"),
            QmlFile::from("qml/MediaContextMenu.qml"),
            QmlFile::from("qml/AddToPlaylistDialog.qml"),
            QmlFile::from("qml/MediaGridPage.qml"),
            QmlFile::from("qml/MixPage.qml"),
            QmlFile::from("qml/FeedPage.qml"),
            QmlFile::from("qml/SortMenu.qml"),
            QmlFile::from("qml/SettingRow.qml"),
            QmlFile::from("qml/PlaybackSettings.qml"),
            QmlFile::from("qml/ScrobbleSettings.qml"),
            QmlFile::from("qml/NetworkSettings.qml"),
            QmlFile::from("qml/HomePage.qml"),
            QmlFile::from("qml/SearchPage.qml"),
            QmlFile::from("qml/AlbumPage.qml"),
            QmlFile::from("qml/ArtistPage.qml"),
            QmlFile::from("qml/PlaylistPage.qml"),
            QmlFile::from("qml/PlaylistEditDialog.qml"),
            QmlFile::from("qml/ScrollMemory.qml"),
            QmlFile::from("qml/Shortcuts.qml"),
            QmlFile::from("qml/ShortcutsHelp.qml"),
            QmlFile::from("qml/SignalPathPanel.qml"),
            QmlFile::from("qml/GeneralSettings.qml"),
            QmlFile::from("qml/DiscordSettings.qml"),
            QmlFile::from("qml/McpSettings.qml"),
            QmlFile::from("qml/OverlaySettings.qml"),
            QmlFile::from("qml/UtilitiesSettings.qml"),
            QmlFile::from("qml/SettingsField.qml"),
            QmlFile::from("qml/SettingsButton.qml"),
            QmlFile::from("qml/MiniPlayerWindow.qml"),
            QmlFile::from("qml/PlayActions.qml"),
            QmlFile::from("qml/StickyHeader.qml"),
            QmlFile::from("qml/ProfilePage.qml"),
            QmlFile::from("qml/ProfileEditDialog.qml"),
            QmlFile::from("qml/UserMenu.qml"),
            QmlFile::from("qml/ViewAllPage.qml"),
            QmlFile::from("qml/ArtistTracksPage.qml"),
            QmlFile::from("qml/VideoPlayerView.qml"),
            QmlFile::from("qml/VideoCover.qml"),
        ]),
    )
    .qrc("qml/resources.qrc")
    .qt_module("Network")
    .files([
        "src/bridge/auth.rs",
        "src/bridge/catalog.rs",
        "src/bridge/favorites.rs",
        "src/bridge/feed.rs",
        "src/bridge/home.rs",
        "src/bridge/library.rs",
        "src/bridge/mix.rs",
        "src/bridge/nowplaying.rs",
        "src/bridge/player.rs",
        "src/bridge/playlists.rs",
        "src/bridge/search.rs",
        "src/bridge/settings.rs",
        "src/bridge/signalpath.rs",
        "src/bridge/profile.rs",
        "src/bridge/viewall.rs",
        "src/bridge/video.rs",
        "src/bridge/theme.rs",
        "src/bridge/window.rs",
        "src/bridge/artistcard.rs",
    ])
    .build();
}
