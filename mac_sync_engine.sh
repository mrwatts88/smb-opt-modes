#!/bin/sh
# P0.11 — resync the Mac's engine to the committed patch and rebuild it.
#
# `third_party/smb-opt` is an untracked clone of MrWint's repo; its only channel into this
# project is `tools/smb-opt-modes.patch`, regenerated on the primary box at commit time.
# So whenever that patch changes on main, the Mac's engine is STALE and every number it
# produces is from the wrong build. Run this after any pull that touches the patch.
#
# Writes a provenance stamp (third_party/smb-opt/.built-from) that tools/mac_run.sh checks,
# so a stale engine is caught rather than silently used.
#
# usage: tools/mac_sync_engine.sh   — RUN THIS ON THE MAC (its $REPO is the local clone: running it on
#        the Fedora box resets the PRIMARY engine tree and git-cleans target/). From the Fedora box:
#        ssh mac "cd /Users/mattwatts/code/smb && git pull -q laptop main && zsh -l -c tools/mac_sync_engine.sh"
set -e
REPO=$(cd "$(dirname "$0")/.." && pwd)
PINNED=daa44287bc9ccab7e85b430e80bf7dff77542542
PATCH="$REPO/tools/smb-opt-modes.patch"
SRC="$REPO/third_party/smb-opt"

[ -f "$PATCH" ] || { echo "$0: no $PATCH" >&2; exit 1; }
[ -d "$SRC/.git" ] || { echo "$0: no clone at $SRC — run tools/build_core.sh first" >&2; exit 1; }

echo "==> resetting $SRC to $PINNED"
cd "$SRC"
# --hard also clears the index: the patch adds new files, and if they were ever
# intent-to-added (git add -N) they count as tracked and `git clean` would skip them,
# making the reapply fail with "already exists in working directory".
git reset -q --hard "$PINNED"
git clean -fdq
echo "==> applying $(basename "$PATCH")"
git apply "$PATCH"

echo "==> rebuilding (arm64, in the container)"
cd "$REPO"
# the guard would (correctly) refuse a stale engine; this IS the fix for that.
MAC_RUN_ALLOW_STALE=1 tools/mac_run.sh -- sh -c "cd third_party/smb-opt && cargo build --release"

# Stamp what this binary was built from, so mac_run.sh can detect drift.
PATCH_HASH=$(shasum -a 256 "$PATCH" 2>/dev/null || sha256sum "$PATCH")
COMMIT=$(git -C "$REPO" rev-parse HEAD)
printf 'patch_sha256 %s\nrepo_commit  %s\n' "${PATCH_HASH%% *}" "$COMMIT" > "$SRC/.built-from"

echo "==> done. built from repo commit $COMMIT"
echo "    Run the control gate before trusting any result:"
echo "    tools/mac_run.sh -- third_party/smb-opt/target/release/smb-opt \\"
echo "      bfscx W42Main data/wr/wr_inputs.bin 6584 575 587 --lift 0 --check-path 12"
echo "    expected layers: 6 16 34 70 134 673 3472 16472 69489 257001"
