#!/usr/bin/env bash
# bootstrap.sh - install restic (+ deps) for this distro and optionally enable
# the daily backup timer.
#   ./bootstrap.sh           install restic
#   ./bootstrap.sh --timer   also install + enable the systemd --user timer
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
distro() { [ -r /etc/os-release ] && . /etc/os-release && echo "${ID:-} ${ID_LIKE:-}"; }

if ! command -v restic >/dev/null; then
  echo "== Installing restic for: $(distro)"
  case "$(distro)" in
    *bazzite*|*fedora*) rpm-ostree install --idempotent restic || sudo rpm-ostree install --idempotent restic ;;
    *cachyos*|*arch*)   sudo pacman -S --needed --noconfirm restic ;;
    *) echo "!! install 'restic' with your package manager"; exit 1 ;;
  esac
else
  echo "== restic present: $(restic version | head -1)"
fi

if [ "${1:-}" = "--timer" ]; then
  echo "== Installing user timer"
  mkdir -p "$HOME/.config/systemd/user"
  # Point the unit at this checkout
  sed "s#@HERE@#$HERE#g" "$HERE/systemd/beaver.service" > "$HOME/.config/systemd/user/beaver.service"
  install -m644 "$HERE/systemd/beaver.timer" "$HOME/.config/systemd/user/beaver.timer"
  systemctl --user daemon-reload
  systemctl --user enable --now beaver.timer
  echo "   enabled: $(systemctl --user is-enabled beaver.timer)"
  echo "   next run: $(systemctl --user list-timers beaver.timer --no-legend 2>/dev/null | awk '{print $1, $2}')"
fi

echo "== Next: cp config.env.example config.env && chmod 600 config.env  (then edit), then ./backup.sh"
