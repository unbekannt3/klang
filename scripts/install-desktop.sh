#!/usr/bin/env bash
# Register klang with the desktop so KWin can find its icon.
#
# On Wayland the compositor matches a window to a .desktop file by app id, and
# Qt derives that id from the executable name — hence klang.desktop, not the
# reverse-DNS name. (The reverse-DNS id is still used for the MPRIS bus name,
# which is a separate namespace.)

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
SHARE="${XDG_DATA_HOME:-$HOME/.local/share}"

install -Dm644 "$REPO_ROOT/assets/klang.desktop" "$SHARE/applications/klang.desktop"

for size in 16 22 32 48 64 128 256 512; do
  install -Dm644 "$REPO_ROOT/assets/icons/klang-$size.png" \
    "$SHARE/icons/hicolor/${size}x${size}/apps/klang.png"
done

# Point Exec at the built binary so launching from the menu works before an
# install into PATH.
sed -i "s|^Exec=.*|Exec=$REPO_ROOT/target/debug/klang|" "$SHARE/applications/klang.desktop"

update-desktop-database "$SHARE/applications" 2>/dev/null || true
gtk-update-icon-cache -f -t "$SHARE/icons/hicolor" 2>/dev/null || true

echo "installed: $SHARE/applications/klang.desktop"
echo "icons:     $SHARE/icons/hicolor/*/apps/klang.png"
