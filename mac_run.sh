#!/bin/sh
# P0.11 — run a command on the Mac overflow host inside the arm64 Linux container.
#
# The Mac cannot run smb-opt natively (see tools/Dockerfile.smbopt), so every invocation
# goes through here. This is also the Mac's answer to the "never start a search without a
# cgroup cap" rule at the top of STATUS "Running jobs": macOS has no `systemd-run --scope
# -p MemoryMax=`, but a container gets a real cgroup, and --memory-swap equal to --memory
# forbids swap the way MemorySwapMax=0 does.
#
# usage: tools/mac_run.sh [-m MEM] -- <command> [args...]     (paths relative to repo root)
#   -m MEM   hard memory cap, docker syntax (default 8g)
#
# Keep -m meaningfully below the Docker VM's own total (11.67 GiB) — a cap above it does not
# fail cleanly, the VM OOM-kills the container, and the layer files are streamed through the
# VM's page cache, which lives in that same budget. The 8g default mirrors the Fedora box,
# where run 4 sits at an 8G cap with ~3.2 GB anon and the rest page cache. Raise the VM in
# Docker Desktop's GUI (Settings -> Resources -> Advanced), NOT via settings-store.json:
# see docs/experiments/P0.11-two-box.md.
#
# example:
#   tools/mac_run.sh -m 6g -- third_party/smb-opt/target/release/smb-opt bfscx W42Main ...
set -e
export PATH="$PATH:/usr/local/bin"   # docker is not on the non-interactive ssh PATH (P0.11d #4)
MEM=8g
while [ $# -gt 0 ]; do
  case "$1" in
    -m) MEM=$2; shift 2 ;;
    --) shift; break ;;
    *)  echo "usage: $0 [-m MEM] -- <command> [args...]" >&2; exit 2 ;;
  esac
done
[ $# -gt 0 ] || { echo "$0: no command given" >&2; exit 2; }

REPO=$(cd "$(dirname "$0")/.." && pwd)

# Staleness guard. third_party/smb-opt is untracked and reaches this project only through
# tools/smb-opt-modes.patch, so a patch change on main leaves the Mac's binary built from
# the wrong source — and its numbers silently wrong. Refuse to run the engine in that state.
STAMP="$REPO/third_party/smb-opt/.built-from"
PATCH="$REPO/tools/smb-opt-modes.patch"
if [ -f "$PATCH" ]; then
  NOW=$(shasum -a 256 "$PATCH" 2>/dev/null || sha256sum "$PATCH" 2>/dev/null || true)
  NOW=${NOW%% *}
  WAS=$(awk '/^patch_sha256/ { print $2 }' "$STAMP" 2>/dev/null || true)
  if [ "$NOW" != "$WAS" ]; then
    echo "WARNING: the Mac's smb-opt build is STALE or unstamped." >&2
    echo "         tools/smb-opt-modes.patch has changed since it was built." >&2
    echo "         Fix with: tools/mac_sync_engine.sh" >&2
    case "$*" in
      *target/release/smb-opt*)
        [ "${MAC_RUN_ALLOW_STALE:-}" = "1" ] || {
          echo "REFUSING to run the engine from a stale build." >&2
          echo "(override for a non-engine use with MAC_RUN_ALLOW_STALE=1)" >&2
          exit 3; }
        ;;
    esac
  fi
fi

exec docker run --rm \
  --memory="$MEM" --memory-swap="$MEM" \
  --volume "$REPO":/work --workdir /work \
  --user "$(id -u):$(id -g)" \
  smb-opt-build:2018 "$@"
