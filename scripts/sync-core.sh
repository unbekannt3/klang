#!/usr/bin/env bash
# Merge upstream (lullabyX/sone) changes into crates/klang-core.
#
# crates/klang-core/src/<path> mirrors upstream src-tauri/src/<path>. The tag
# `upstream-base` marks the upstream commit our current files were derived from,
# so every file gets a proper three-way merge:
#
#   base   = <upstream-base>:src-tauri/src/<path>
#   theirs = <new-ref>:src-tauri/src/<path>
#   ours   = crates/klang-core/src/<path> (working tree)
#
# Files upstream has not touched since `upstream-base` are skipped. Files we
# never modified are taken verbatim. Everything else is merged, and conflicts
# are left in the working tree with markers for you to resolve.
#
# Usage: scripts/sync-core.sh [upstream-ref]        (default: upstream/master)
#        scripts/sync-core.sh --accept              (move upstream-base after a clean run)

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
cd "$REPO_ROOT"

CORE_DIR="crates/klang-core/src"
UPSTREAM_DIR="src-tauri/src"
BASE_TAG="upstream-base"

accept=0
ref="upstream/master"
for arg in "$@"; do
  case "$arg" in
    --accept) accept=1 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) ref="$arg" ;;
  esac
done

git rev-parse -q --verify "$BASE_TAG" >/dev/null || {
  echo "error: tag '$BASE_TAG' missing — it marks the upstream commit klang-core was derived from." >&2
  exit 1
}
base="$(git rev-parse "$BASE_TAG^{commit}")"

echo "==> fetching upstream"
git fetch --quiet upstream

new="$(git rev-parse "$ref^{commit}")"
if [[ "$base" == "$new" ]]; then
  echo "already at $ref ($(git log --oneline -1 "$new")) — nothing to do"
  exit 0
fi

echo "    base $(git log --oneline -1 "$base")"
echo "    new  $(git log --oneline -1 "$new")"
echo

# Upstream paths present in each commit, restricted to the mirrored directory.
list_paths() { git ls-tree -r --name-only "$1" -- "$UPSTREAM_DIR" | sed "s|^$UPSTREAM_DIR/||"; }

mapfile -t base_paths < <(list_paths "$base")
mapfile -t new_paths < <(list_paths "$new")

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

taken=0; merged=0; conflicted=0; skipped=0; local_only=0
conflicts=()

for path in "${new_paths[@]}"; do
  ours="$CORE_DIR/$path"

  # New file upstream: take it, but only warn — it may belong to a module we
  # deleted (commands/, lib.rs) rather than to the core.
  if ! git cat-file -e "$base:$UPSTREAM_DIR/$path" 2>/dev/null; then
    echo "  NEW UPSTREAM   $path  (not merged — decide whether klang needs it)"
    continue
  fi

  git show "$base:$UPSTREAM_DIR/$path" > "$tmp/base" 2>/dev/null
  git show "$new:$UPSTREAM_DIR/$path"  > "$tmp/theirs"

  # Upstream did not change this file.
  if cmp -s "$tmp/base" "$tmp/theirs"; then
    skipped=$((skipped + 1))
    continue
  fi

  # We deleted this file (commands/, lib.rs, …) — upstream churn does not apply.
  if [[ ! -f "$ours" ]]; then
    echo "  DROPPED HERE   $path  (upstream changed it; klang does not carry it)"
    local_only=$((local_only + 1))
    continue
  fi

  # We never touched it: take upstream verbatim.
  if cmp -s "$tmp/base" "$ours"; then
    cp "$tmp/theirs" "$ours"
    echo "  TAKEN          $path"
    taken=$((taken + 1))
    continue
  fi

  cp "$ours" "$tmp/ours"
  if git merge-file -L "klang" -L "upstream-base" -L "upstream" \
       "$tmp/ours" "$tmp/base" "$tmp/theirs" >/dev/null 2>&1; then
    cp "$tmp/ours" "$ours"
    echo "  MERGED         $path"
    merged=$((merged + 1))
  else
    cp "$tmp/ours" "$ours"
    echo "  CONFLICT       $path"
    conflicts+=("$ours")
    conflicted=$((conflicted + 1))
  fi
done

# Files upstream removed.
for path in "${base_paths[@]}"; do
  if ! git cat-file -e "$new:$UPSTREAM_DIR/$path" 2>/dev/null && [[ -f "$CORE_DIR/$path" ]]; then
    echo "  REMOVED UPSTREAM $path  (still present here — review)"
  fi
done

echo
echo "==> $taken taken, $merged merged, $conflicted conflicted, $skipped unchanged, $local_only dropped here"

if (( conflicted > 0 )); then
  echo
  echo "Resolve the conflict markers, then re-run with --accept:"
  printf '  %s\n' "${conflicts[@]}"
  exit 1
fi

if (( accept == 1 )); then
  git tag -f "$BASE_TAG" "$new"
  echo "==> moved $BASE_TAG to $(git log --oneline -1 "$new")"
else
  echo
  echo "Build and test, then run: scripts/sync-core.sh --accept $ref"
fi
