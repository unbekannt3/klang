#!/usr/bin/env bash
# Build an installable .deb from the current checkout.
#
#     scripts/build-deb.sh          # build, leave the .deb in dist/
#     scripts/build-deb.sh --keep   # …and keep the build tree in dist/deb-build
#
# The build runs in a debian:trixie container, so it works from any host.
# Trixie is the floor: Ubuntu 24.04 ships Qt 6.4 and the QML needs 6.8.
#
# The tarball comes from git, so uncommitted changes are not packaged — the
# debian/ directory is copied from the working tree.

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
IMAGE="debian:trixie"
# Rootless podman maps container root onto the invoking user, so the .deb lands
# owned by us. Under docker it would be root-owned.
ENGINE="${KLANG_CONTAINER_ENGINE:-podman}"
VERSION="$(sed -n '1s/.*(\(.*\)).*/\1/p' "$REPO_ROOT/packaging/deb/changelog")"
WORK="$REPO_ROOT/dist/deb-build"
SRC="$WORK/klang-${VERSION%-*}"
DIST="$REPO_ROOT/dist"

keep=false
[[ "${1:-}" == "--keep" ]] && keep=true

rm -rf "$WORK"
mkdir -p "$SRC" "$DIST"
git -C "$REPO_ROOT" archive --format=tar HEAD | tar -x -C "$SRC"
cp -r "$REPO_ROOT/packaging/deb" "$SRC/debian"
chmod +x "$SRC/debian/rules"

# cargo needs the network for crates.io.
"$ENGINE" run --rm -v "$WORK:/work:z" -w "/work/$(basename "$SRC")" "$IMAGE" \
  bash -euo pipefail -c '
    export DEBIAN_FRONTEND=noninteractive
    echo "deb http://deb.debian.org/debian trixie-backports main" \
      >/etc/apt/sources.list.d/backports.list
    apt-get update -qq
    apt-get install -y --no-install-recommends build-essential lintian
    # cxx 1.0 needs rustc 1.88; trixie has 1.85. Pull just the toolchain from
    # backports — pointing build-dep at the whole suite would drag Qt with it.
    apt-get install -y --no-install-recommends -t trixie-backports rustc cargo
    apt-get build-dep -y --no-install-recommends ./
    dpkg-buildpackage -b -us -uc
    lintian --no-tag-display-limit ../klang_*.deb || true
  '

find "$WORK" -maxdepth 1 -name '*.deb' -exec cp {} "$DIST/" \;

# A fresh container proves the dependencies actually resolve against the
# archive, which the build container cannot show — it has the build deps in it.
"$ENGINE" run --rm -v "$DIST:/dist:z" "$IMAGE" \
  bash -euo pipefail -c '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y /dist/klang_*_*.deb
    test -x /usr/bin/klang
    ! ldd /usr/bin/klang | grep "not found"
  '

$keep || rm -rf "$WORK"

echo
echo "built:"
find "$DIST" -maxdepth 1 -name 'klang_*.deb' -printf '  %p\n'
