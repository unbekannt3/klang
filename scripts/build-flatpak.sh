#!/usr/bin/env bash
# Build klang as a Flatpak, into an OSTree repo and a single-file bundle.
#
#     scripts/build-flatpak.sh           # build, leave both in dist/
#     scripts/build-flatpak.sh --install # …and install the bundle for this user
#
# Nothing here goes near Flathub: the repo is ours, and the .flatpakref points
# at wherever it ends up published.

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
MANIFEST="$REPO_ROOT/packaging/flatpak/me.unbk.klang.yml"
DIST="$REPO_ROOT/dist"
REPO="$DIST/flatpak-repo"
BUILD="$DIST/flatpak-build"
BUNDLE="$DIST/klang.flatpak"

install_after=false
[[ "${1:-}" == "--install" ]] && install_after=true

if ! command -v flatpak-builder >/dev/null; then
  echo "flatpak-builder is missing: sudo dnf install flatpak-builder" >&2
  exit 1
fi

# The KDE runtime and the Rust extension come from Flathub even though the app
# never goes there.
flatpak install --or-update --user --noninteractive flathub \
  org.kde.Platform//6.11 org.kde.Sdk//6.11 \
  org.freedesktop.Sdk.Extension.rust-stable//25.08

rm -rf "$BUILD"
mkdir -p "$DIST"

flatpak-builder --user --force-clean --repo="$REPO" "$BUILD" "$MANIFEST"

# Unsigned: the .flatpakref turns gpg verification off to match. Signing needs
# a key we would have to distribute anyway.
flatpak build-bundle "$REPO" "$BUNDLE" me.unbk.klang stable

echo
echo "repo:   $REPO"
echo "bundle: $BUNDLE"

if $install_after; then
  flatpak install --user --noninteractive --bundle "$BUNDLE"
  echo "run with: flatpak run me.unbk.klang"
fi
