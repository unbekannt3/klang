# klang

A KDE-native TIDAL client for Linux. Private fork of
[lullabyX/sone](https://github.com/lullabyX/sone), replacing Tauri and WebKitGTK
with Qt Quick and Kirigami.

Built for one target: Fedora KDE on Wayland. No Flatpak, no cross-distro
packaging, no Windows or macOS paths. Upstream's README is kept at
[docs/README.sone.md](docs/README.sone.md).

## Why

WebKitGTK's DMA-BUF renderer allocates a fresh GBM buffer per composited layer
per window size. During a window resize on a 4K display that runs into tens of
gigabytes of VRAM — enough to OOM a 24 GiB card
([sone#199](https://github.com/lullabyX/sone/issues/199)). Qt Quick renders one
scene graph into one framebuffer, so that class of problem does not exist.

The audio stack is the good part of sone and is kept intact: bit-perfect ALSA
output, gapless playback, GStreamer pipeline probing, MPRIS, scrobbling.

## Layout

```
crates/klang-core/    the inherited core — TIDAL API, playback, MPRIS,
                      scrobbling, cache, MCP server, OBS overlay
crates/klang-qt/      cxx-qt bridge, main(), and the QML under qml/
src/                  sone's React UI, kept as a reference while porting
scripts/sync-core.sh  three-way merge of upstream fixes into klang-core
```

`crates/klang-core/src/<path>` mirrors upstream `src-tauri/src/<path>` one to
one. The tag `upstream-base` marks the upstream commit the current files derive
from, so `scripts/sync-core.sh` can merge upstream changes file by file.

`tauri::AppHandle` was used for exactly three things — emitting events, reaching
the shared `AppState`, and raising the window. `app::AppContext` provides those
three and nothing else. Its `Emitter` trait mirrors `tauri::Emitter` down to the
method name and `Result` return, so all ~87 `.emit(...)` call sites in the core
are unchanged from upstream and never conflict on merge.

## Building

Fedora 44:

```sh
sudo dnf install rust cargo alsa-lib-devel gstreamer1-devel \
    gstreamer1-plugins-base-devel glib2-devel openssl-devel pkgconf-pkg-config
cargo test -p klang-core
```

Boot the core with no UI attached and see what it finds:

```sh
cargo run -p klang-core --example smoke
```

Run the app:

```sh
cargo run -p klang-qt
```

Sign in with the device code it shows: open link.tidal.com in a browser and
type the code. The session is then remembered.

## Configuration

Settings, cache and logs live in `~/.config/klang`, and the MPRIS name is
`me.unbk.klang`, so klang runs beside sone without touching its profile or
stealing its D-Bus name.

`$KLANG_CONFIG_DIR` overrides the location. To start from an existing sone
login instead of signing in again, copy the profile across once:

```sh
cp -r ~/.var/app/io.github.lullabyX.sone/config/sone ~/.config/klang
```

## Upstream

```sh
scripts/sync-core.sh            # merge upstream/master, report what happened
scripts/sync-core.sh --accept   # after building and testing cleanly
```

Files upstream has not touched are skipped, files klang never modified are taken
verbatim, and the rest gets a three-way merge. `commands/` and `lib.rs`'s `run()`
do not exist here and are never synced.

## Licence

GPL-3.0-only, inherited from sone. Copyright in the original work remains with
lullabyX and sone's contributors.
