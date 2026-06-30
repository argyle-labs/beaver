#!/usr/bin/env bash
# backup.sh - capture system state, then restic-backup home/user data to every
# configured destination (NAS / external drive / cloud).
#   ./backup.sh              full run
#   ./backup.sh --state-only just refresh the state manifest, no data backup
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$HERE/config.env" ] || { echo "Missing config.env (cp config.env.example config.env)"; exit 1; }
# shellcheck disable=SC1091
source "$HERE/config.env"
export RESTIC_PASSWORD_FILE STATE_DIR

echo "== Capturing system state"
STATE_DIR="$STATE_DIR" bash "$HERE/lib/state.sh" capture

[ "${1:-}" = "--state-only" ] && { echo "state-only: done"; exit 0; }

# Build restic args from config
EXCLUDE_ARGS=(); for e in "${EXCLUDES[@]:-}"; do [ -n "$e" ] && EXCLUDE_ARGS+=(--exclude "$e"); done
PATHS=("${BACKUP_PATHS[@]}" "$STATE_DIR")

backup_to() { # $1=label $2=repo
  local label="$1" repo="$2"; [ -z "$repo" ] && return 0
  echo "== [$label] $repo"
  export RESTIC_REPOSITORY="$repo"
  restic snapshots >/dev/null 2>&1 || { echo "   initializing repo"; restic init || { echo "   !! init failed for $label"; return 1; }; }
  restic backup --verbose --tag "$(hostname)" "${EXCLUDE_ARGS[@]}" "${PATHS[@]}" \
    || { echo "   !! backup failed for $label"; return 1; }
  echo "   pruning ($KEEP_DAILY/$KEEP_WEEKLY/$KEEP_MONTHLY d/w/m)"
  restic forget --prune --keep-daily "$KEEP_DAILY" --keep-weekly "$KEEP_WEEKLY" --keep-monthly "$KEEP_MONTHLY" || true
}

rc=0
backup_to nas      "${NAS_REPO:-}"      || rc=1
backup_to extdrive "${EXTDRIVE_REPO:-}" || rc=1
backup_to cloud    "${CLOUD_REPO:-}"    || rc=1
echo "== Done (exit $rc)"; exit $rc
