#!/usr/bin/env bash
# Build an installable RPM from the current checkout.
#
#     scripts/build-rpm.sh          # build, leave the rpm in dist/
#     scripts/build-rpm.sh --install # …and hand it to dnf
#
# The tarball comes from git, so uncommitted changes are not packaged.

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
SPEC="$REPO_ROOT/packaging/rpm/klang.spec"
VERSION="$(rpmspec -q --qf '%{version}\n' "$SPEC" | head -1)"
TOPDIR="$REPO_ROOT/dist/rpmbuild"
DIST="$REPO_ROOT/dist"

install_after=false
[[ "${1:-}" == "--install" ]] && install_after=true

rm -rf "$TOPDIR"
mkdir -p "$TOPDIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS} "$DIST"

# %autosetup expects the tree under <name>-<version>/.
git -C "$REPO_ROOT" archive --format=tar.gz \
  --prefix="klang-$VERSION/" -o "$TOPDIR/SOURCES/klang-$VERSION.tar.gz" HEAD

cp "$SPEC" "$TOPDIR/SPECS/"

# cargo needs the network for crates.io; rpmbuild does not sandbox it.
rpmbuild --define "_topdir $TOPDIR" -ba "$TOPDIR/SPECS/klang.spec"

find "$TOPDIR/RPMS" "$TOPDIR/SRPMS" -name '*.rpm' -exec cp {} "$DIST/" \;
echo
echo "built:"
find "$DIST" -maxdepth 1 -name '*.rpm' -newer "$SPEC" -printf '  %p\n'

if $install_after; then
  sudo dnf install -y "$DIST"/klang-"$VERSION"-*.x86_64.rpm
fi
