#!/bin/sh
# Regenerate tools/smb-opt-modes.patch from the smb-opt clone, with the guards that
# session 16 learned the hard way. See docs/search-runbook.md §5.
#
# The clone MUST sit at the pin with every modification as an uncommitted working-tree
# change. The patch is `git diff` against that pin, so a commit in the clone moves HEAD
# and makes `git diff` return EMPTY -- which regenerates a patch that silently applies
# nothing. The Mac would then rebuild from unmodified upstream and every number it
# produced would be wrong, with no error anywhere.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CLONE="$ROOT/third_party/smb-opt"
PATCH="$ROOT/tools/smb-opt-modes.patch"
PIN=daa44287bc9ccab7e85b430e80bf7dff77542542

HEAD=$(git -C "$CLONE" rev-parse HEAD)
if [ "$HEAD" != "$PIN" ]; then
  echo "REFUSING: the clone's HEAD is $HEAD, not the pin $PIN." >&2
  echo "Someone committed in the clone (or checked out something else). Recover with:" >&2
  echo "  git -C $CLONE reset --mixed $PIN" >&2
  echo "then re-run this script (it re-intent-adds the untracked sources for you)." >&2
  exit 1
fi

# Intent-add every untracked source file, or `git diff` silently omits it (P0.11 §7 #13:
# a regen that dropped three of them applied cleanly and failed the Mac build).
git -C "$CLONE" ls-files --others --exclude-standard -- 'src/*.rs' 'src/**/*.rs' \
  | while read -r f; do git -C "$CLONE" add -N -- "$f"; done

TMP=$(mktemp)
git -C "$CLONE" diff > "$TMP"

NEW=$(wc -l < "$TMP")
if [ "$NEW" -lt 100 ]; then
  echo "REFUSING: regenerated patch is only $NEW lines -- that is not a real patch." >&2
  rm -f "$TMP"; exit 1
fi
if [ -f "$PATCH" ]; then
  OLD=$(wc -l < "$PATCH")
  MIN=$(( OLD * 9 / 10 ))
  if [ "$NEW" -lt "$MIN" ] && [ "$1" != "--force" ]; then
    echo "REFUSING: patch would shrink $OLD -> $NEW lines (>10%). Re-run with --force if intended." >&2
    rm -f "$TMP"; exit 1
  fi
fi
mv "$TMP" "$PATCH"
echo "regenerated $PATCH ($NEW lines) from clone at $PIN"
