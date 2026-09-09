#!/usr/bin/env bash
# Build an installable pacman package from the current checkout.
#
#     scripts/build-arch.sh          # build, leave the .pkg.tar.zst in dist/
#     scripts/build-arch.sh --keep   # …and keep the build tree in dist/arch-build
#
# The build runs in an archlinux:latest container, so it works from any host.
#
# The tarball comes from git, so uncommitted changes are not packaged — the
# PKGBUILD is copied from the working tree.

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
PKGBUILD="$REPO_ROOT/packaging/arch/PKGBUILD"
IMAGE="archlinux:latest"
ENGINE="${KLANG_CONTAINER_ENGINE:-podman}"
VERSION="$(sed -n 's/^pkgver=//p' "$PKGBUILD")"
WORK="$REPO_ROOT/dist/arch-build"
DIST="$REPO_ROOT/dist"

keep=false
[[ "${1:-}" == "--keep" ]] && keep=true

rm -rf "$WORK"
mkdir -p "$WORK" "$DIST"
git -C "$REPO_ROOT" archive --format=tar.gz \
  --prefix="klang-$VERSION/" -o "$WORK/klang-$VERSION.tar.gz" HEAD
cp "$PKGBUILD" "$WORK/"

# cargo needs the network for crates.io.
"$ENGINE" run --rm -v "$WORK:/work:z" "$IMAGE" \
  bash -euo pipefail -c '
    # makepkg builds as its own user, so the tree has to be handed back to
    # whatever the mount maps the caller to — rootless podman sees us as root
    # here, docker as real root the runner cannot touch. Either way, without
    # this the host is left with a build tree it cannot delete.
    trap "chown -R $(stat -c %u:%g /work) /work" EXIT

    pacman -Syu --noconfirm --needed base-devel
    # makepkg refuses to run as root, and its --syncdeps calls pacman via sudo.
    useradd -m builder
    echo "builder ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/builder
    chown -R builder /work
    su builder -c "cd /work && makepkg --syncdeps --noconfirm"
  '

find "$WORK" -maxdepth 1 -name '*.pkg.tar.zst' -exec cp {} "$DIST/" \;

# A fresh container proves the dependencies actually resolve against the
# repos, which the build container cannot show — it has the build deps in it.
"$ENGINE" run --rm -v "$DIST:/dist:z" "$IMAGE" \
  bash -euo pipefail -c '
    pacman -Syu --noconfirm
    # klang-[0-9]* skips the klang-debug package makepkg also emits.
    pacman -U --noconfirm /dist/klang-[0-9]*.pkg.tar.zst
    test -x /usr/bin/klang
    ! ldd /usr/bin/klang | grep "not found"
  '

$keep || rm -rf "$WORK"

echo
echo "built:"
find "$DIST" -maxdepth 1 -name 'klang-*.pkg.tar.zst' -printf '  %p\n'
