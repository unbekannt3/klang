#!/usr/bin/env bash
# Build klang as a Flatpak, into an OSTree repo and a single-file bundle.
#
#     scripts/build-flatpak.sh           # build, leave both in dist/
#     scripts/build-flatpak.sh --install # …and install the bundle for this user
#
# Nothing here goes near Flathub. The bundle installs on its own; the OSTree
# repo is only useful once it is served over HTTP somewhere, so the .flatpakref
# that points at it is written only when $KLANG_FLATPAK_URL says where.

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
MANIFEST="$REPO_ROOT/packaging/flatpak/me.unbk.klang.yml"
DIST="$REPO_ROOT/dist"
REPO="$DIST/flatpak-repo"
BUILD="$DIST/flatpak-build"
BUNDLE="$DIST/klang.flatpak"
REF="$DIST/me.unbk.klang.flatpakref"
# Where the OSTree repo above is served from, if anywhere.
REPO_URL="${KLANG_FLATPAK_URL:-}"

install_after=false
[[ "${1:-}" == "--install" ]] && install_after=true

for tool in flatpak-builder eu-strip; do
  command -v "$tool" >/dev/null && continue
  # eu-strip runs on the host when the debug info is split out, and Debian's
  # flatpak-builder does not depend on it — the build otherwise gets all the
  # way through the Rust compile before failing.
  echo "$tool is missing: sudo dnf install flatpak-builder elfutils" >&2
  exit 1
done

# The KDE runtime and the Rust extension come from Flathub even though the app
# never goes there.
flatpak install --or-update --user --noninteractive flathub \
  org.kde.Platform//6.11 org.kde.Sdk//6.11 \
  org.freedesktop.Sdk.Extension.rust-stable//25.08

rm -rf "$BUILD"
mkdir -p "$DIST"

flatpak-builder --user --force-clean --repo="$REPO" "$BUILD" "$MANIFEST"

flatpak build-bundle "$REPO" "$BUNDLE" me.unbk.klang stable

if [[ -n "$REPO_URL" ]]; then
  # Unsigned, so gpg verification stays off: signing needs a key we would have
  # to distribute alongside the repo anyway.
  cat >"$REF" <<EOF
[Flatpak Ref]
Title=Klang
Name=me.unbk.klang
Branch=stable
Url=${REPO_URL%/}/
IsRuntime=false
RuntimeRepo=https://dl.flathub.org/repo/flathub.flatpakrepo
EOF
fi

echo
echo "repo:   $REPO"
echo "bundle: $BUNDLE"
if [[ -n "$REPO_URL" ]]; then
  echo "ref:    $REF"
else
  echo "ref:    not written — set \$KLANG_FLATPAK_URL to where $REPO will be served"
fi

if $install_after; then
  flatpak install --user --noninteractive --bundle "$BUNDLE"
  echo "run with: flatpak run me.unbk.klang"
fi
