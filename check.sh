#!/usr/bin/env bash
# check.sh - health-check the beaver backup setup and report issues. Verifies the
# encryption key, each configured restic repo's reachability, the age of the most
# recent snapshot, and the freshness of the captured state manifest.
#
#   ./check.sh            human-readable report (default)
#   ./check.sh --json     machine-readable issues (shape mirrors orca's Issue type)
#   ./check.sh --verify   also run `restic check` (slower; reads repo structure)
#   ./check.sh --notify   push a summary to NTFY_URL if any WARN/CRIT (see config.env)
#
# Exit code: 0 = all OK, 1 = at least one WARN, 2 = at least one CRIT.
# Read-only: never writes to a repo (a backup you never verify is a guess).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$HERE/config.env" ] || { echo "Missing config.env (cp config.env.example config.env)"; exit 1; }
# shellcheck disable=SC1091
source "$HERE/config.env"
export RESTIC_PASSWORD_FILE STATE_DIR

MODE="report" DO_VERIFY=0 DO_NOTIFY=0
while [ $# -gt 0 ]; do case "$1" in
  --json)   MODE="json"; shift ;;
  --verify) DO_VERIFY=1; shift ;;
  --notify) DO_NOTIFY=1; shift ;;
  --report) MODE="report"; shift ;;
  *) echo "usage: $0 [--json] [--verify] [--notify]"; exit 1 ;;
esac; done

MAX_SNAPSHOT_AGE_DAYS="${MAX_SNAPSHOT_AGE_DAYS:-2}"
MAX_STATE_AGE_DAYS="${MAX_STATE_AGE_DAYS:-2}"

# id | severity(OK|WARN|CRIT) | title | detail
ISSUES=()
issue() { ISSUES+=("$1|$2|$3|$4"); }

file_age_days() { # $1=path -> whole days since mtime, or -1 if missing
  [ -e "$1" ] || { echo -1; return; }
  local now mt; now=$(date +%s); mt=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1")
  echo $(( (now - mt) / 86400 ))
}

check_key() {
  if [ -z "${RESTIC_PASSWORD_FILE:-}" ]; then
    issue key CRIT "No restic password file configured" "RESTIC_PASSWORD_FILE unset in config.env"
  elif [ ! -f "$RESTIC_PASSWORD_FILE" ]; then
    issue key CRIT "restic key file missing" "$RESTIC_PASSWORD_FILE not found - repos are UNRECOVERABLE without it"
  else
    local perm; perm=$(stat -c %a "$RESTIC_PASSWORD_FILE" 2>/dev/null || stat -f %A "$RESTIC_PASSWORD_FILE")
    if [ "$perm" != 600 ]; then
      issue key WARN "restic key file is not chmod 600" "$RESTIC_PASSWORD_FILE has mode $perm"
    else
      issue key OK "restic key present" "$RESTIC_PASSWORD_FILE (600)"
    fi
  fi
}

check_repo() { # $1=label $2=repo-uri
  local label="$1" repo="$2"
  [ -z "$repo" ] && return 0   # target not configured
  export RESTIC_REPOSITORY="$repo"
  if ! restic snapshots >/dev/null 2>&1; then
    issue "repo:$label" CRIT "Repo unreachable/uninitialized: $label" "restic could not open $repo"
    return
  fi
  # Age of the newest snapshot for this host.
  local last age
  last=$(restic snapshots --host "$(hostname)" --latest 1 --json 2>/dev/null \
    | grep -o '"time":"[^"]*"' | head -1 | cut -d'"' -f4)
  if [ -z "$last" ]; then
    issue "repo:$label" WARN "No snapshot for $(hostname) on $label" "repo reachable but this host has never backed up here"
    return
  fi
  age=$(( ( $(date +%s) - $(date -d "$last" +%s 2>/dev/null || date -jf %Y-%m-%dT%H:%M:%S "${last%%.*}" +%s) ) / 86400 ))
  if [ "$age" -gt "$MAX_SNAPSHOT_AGE_DAYS" ]; then
    issue "repo:$label" WARN "Stale backup on $label" "newest snapshot is ${age}d old (threshold ${MAX_SNAPSHOT_AGE_DAYS}d)"
  else
    issue "repo:$label" OK "Backup current on $label" "newest snapshot ${age}d old"
  fi
  if [ "$DO_VERIFY" = 1 ]; then
    if restic check >/dev/null 2>&1; then
      issue "verify:$label" OK "restic check passed on $label" "repo structure intact"
    else
      issue "verify:$label" CRIT "restic check FAILED on $label" "repo integrity problem - investigate before trusting it"
    fi
  fi
}

check_state() {
  local age; age=$(file_age_days "${STATE_DIR:-}/distro.txt")
  if [ "$age" -lt 0 ]; then
    issue state WARN "No state manifest captured" "run ./backup.sh --state-only (rebuild-from-scratch data)"
  elif [ "$age" -gt "$MAX_STATE_AGE_DAYS" ]; then
    issue state WARN "State manifest is stale" "${age}d old (threshold ${MAX_STATE_AGE_DAYS}d); packages/units may have drifted"
  else
    issue state OK "State manifest fresh" "${age}d old"
  fi
}

run_checks() {
  check_key
  check_repo nas      "${NAS_REPO:-}"
  check_repo extdrive "${EXTDRIVE_REPO:-}"
  check_repo cloud    "${CLOUD_REPO:-}"
  check_state
}

json_escape() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; printf '%s' "$s"; }
emit_json() {
  printf '{"host":"%s","issues":[' "$(json_escape "$(hostname)")"
  local first=1 i id sev title detail
  for i in "${ISSUES[@]}"; do
    IFS='|' read -r id sev title detail <<<"$i"
    [ "$first" = 1 ] || printf ','; first=0
    printf '{"id":"%s","severity":"%s","title":"%s","detail":"%s"}' \
      "$(json_escape "$id")" "$sev" "$(json_escape "$title")" "$(json_escape "$detail")"
  done
  printf ']}\n'
}

n_warn=0 n_crit=0
tally() { local i id sev; for i in "${ISSUES[@]}"; do IFS='|' read -r id sev _ _ <<<"$i"
  case "$sev" in WARN) n_warn=$((n_warn+1)) ;; CRIT) n_crit=$((n_crit+1)) ;; esac; done; }

emit_report() {
  local i id sev title detail
  for i in "${ISSUES[@]}"; do
    IFS='|' read -r id sev title detail <<<"$i"
    case "$sev" in
      OK)   printf '  \033[32mOK\033[0m   %s\n' "$title" ;;
      WARN) printf '  \033[33mWARN\033[0m %s\n       %s\n' "$title" "$detail" ;;
      CRIT) printf '  \033[31mCRIT\033[0m %s\n       %s\n' "$title" "$detail" ;;
    esac
  done
  echo
  echo "== $((${#ISSUES[@]})) checks, ${n_warn} warn, ${n_crit} crit"
}

notify() {
  [ "$DO_NOTIFY" = 1 ] || return 0
  [ $((n_warn + n_crit)) -gt 0 ] || return 0
  [ -n "${NTFY_URL:-}" ] || { echo "!! --notify set but NTFY_URL empty in config.env"; return 0; }
  local prio title body
  if [ "$n_crit" -gt 0 ]; then prio=high; title="beaver CRIT on $(hostname)"; else prio=default; title="beaver WARN on $(hostname)"; fi
  body="$(printf '%s\n' "${ISSUES[@]}" | awk -F'|' '$2!="OK"{print $2": "$3}')"
  if curl -fsS -H "Title: $title" -H "Priority: $prio" -d "$body" "$NTFY_URL" >/dev/null; then
    echo ">> notified $NTFY_URL"
  else
    echo "!! ntfy push failed"
  fi
}

run_checks
tally
case "$MODE" in json) emit_json ;; report) emit_report ;; esac
notify

worst=0
[ "$n_warn" -gt 0 ] && worst=1
[ "$n_crit" -gt 0 ] && worst=2
exit "$worst"
