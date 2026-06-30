#!/usr/bin/env bash
# restore.sh - restore from a backup target and/or reinstall packages.
#   ./restore.sh --target <nas|extdrive|cloud> [--path DEST] [--snapshot ID]
#   ./restore.sh --packages          reinstall packages from the captured manifest
#   ./restore.sh --target nas --list list snapshots on a target
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$HERE/config.env" ] || { echo "Missing config.env"; exit 1; }
# shellcheck disable=SC1091
source "$HERE/config.env"
export RESTIC_PASSWORD_FILE STATE_DIR

TARGET="" DEST="/" SNAP="latest" DO_LIST=0 DO_PKGS=0
while [ $# -gt 0 ]; do case "$1" in
  --target) TARGET="$2"; shift 2 ;;
  --path)   DEST="$2"; shift 2 ;;
  --snapshot) SNAP="$2"; shift 2 ;;
  --list)   DO_LIST=1; shift ;;
  --packages) DO_PKGS=1; shift ;;
  *) echo "unknown arg: $1"; exit 1 ;;
esac; done

repo_for() { case "$1" in nas) echo "${NAS_REPO:-}";; extdrive) echo "${EXTDRIVE_REPO:-}";; cloud) echo "${CLOUD_REPO:-}";; *) echo "";; esac; }

if [ -n "$TARGET" ]; then
  repo="$(repo_for "$TARGET")"; [ -z "$repo" ] && { echo "target '$TARGET' not configured"; exit 1; }
  export RESTIC_REPOSITORY="$repo"
  if [ "$DO_LIST" = 1 ]; then restic snapshots; exit 0; fi
  echo "== Restoring snapshot '$SNAP' from $TARGET -> $DEST"
  echo "   (data restores under $DEST; use --path \$HOME to restore into your home)"
  restic restore "$SNAP" --target "$DEST" --verbose
fi

if [ "$DO_PKGS" = 1 ]; then
  echo "== Reinstalling packages from manifest ($STATE_DIR)"
  STATE_DIR="$STATE_DIR" bash "$HERE/lib/state.sh" restore-packages
fi

[ -z "$TARGET" ] && [ "$DO_PKGS" = 0 ] && { echo "nothing to do; see: $0 --help-ish (read header)"; exit 1; }
echo "== Done"
