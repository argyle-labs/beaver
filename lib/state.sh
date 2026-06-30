#!/usr/bin/env bash
# lib/state.sh - capture / restore declarative system state (per-distro).
#   state.sh capture           -> write manifests into $STATE_DIR
#   state.sh restore-packages  -> reinstall from manifests
# Sourced helpers also usable directly. Honors $STATE_DIR (default below).
set -euo pipefail
STATE_DIR="${STATE_DIR:-$HOME/.local/state/linux-backup}"

_distro() { [ -r /etc/os-release ] && . /etc/os-release && echo "${ID:-} ${ID_LIKE:-}"; }

capture() {
  mkdir -p "$STATE_DIR"
  echo "$(_distro)" > "$STATE_DIR/distro.txt"
  command -v flatpak >/dev/null && flatpak list --app --columns=application > "$STATE_DIR/flatpak.txt" || true
  systemctl list-unit-files --state=enabled --no-legend 2>/dev/null | awk '{print $1}' > "$STATE_DIR/services-system.txt" || true
  systemctl --user list-unit-files --state=enabled --no-legend 2>/dev/null | awk '{print $1}' > "$STATE_DIR/services-user.txt" || true

  case "$(_distro)" in
    *bazzite*|*fedora*)
      rpm-ostree status > "$STATE_DIR/rpm-ostree-status.txt" 2>/dev/null || true
      # Layered (user-requested) packages and the booted image ref:
      rpm-ostree status --json 2>/dev/null \
        | python3 -c 'import json,sys; d=json.load(sys.stdin)["deployments"][0]; print("\n".join(d.get("requested-packages",[])))' \
        > "$STATE_DIR/layered-packages.txt" 2>/dev/null || true
      rpm-ostree status --json 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["deployments"][0].get("container-image-reference",""))' \
        > "$STATE_DIR/image-ref.txt" 2>/dev/null || true
      ;;
    *cachyos*|*arch*)
      command -v pacman >/dev/null && {
        pacman -Qqen > "$STATE_DIR/pacman-native.txt" 2>/dev/null || true   # explicit, repo
        pacman -Qqem > "$STATE_DIR/pacman-aur.txt"    2>/dev/null || true   # explicit, foreign/AUR
      }
      ;;
  esac
  echo ">> state captured -> $STATE_DIR"
  ls -1 "$STATE_DIR"
}

restore_packages() {
  [ -d "$STATE_DIR" ] || { echo "no state at $STATE_DIR"; return 1; }
  # Flatpaks (all distros)
  if command -v flatpak >/dev/null && [ -s "$STATE_DIR/flatpak.txt" ]; then
    echo ">> restoring flatpaks"; xargs -r -a "$STATE_DIR/flatpak.txt" -I{} flatpak install -y --noninteractive flathub {} || true
  fi
  case "$(_distro)" in
    *bazzite*|*fedora*)
      if [ -s "$STATE_DIR/layered-packages.txt" ]; then
        echo ">> layering rpm-ostree packages (reboot after)"; sudo rpm-ostree install --idempotent $(tr '\n' ' ' < "$STATE_DIR/layered-packages.txt") || true
      fi ;;
    *cachyos*|*arch*)
      [ -s "$STATE_DIR/pacman-native.txt" ] && { echo ">> installing native pkgs"; sudo pacman -S --needed --noconfirm - < "$STATE_DIR/pacman-native.txt" || true; }
      [ -s "$STATE_DIR/pacman-aur.txt" ] && echo ">> AUR pkgs to reinstall with your helper (paru/yay): $(tr '\n' ' ' < "$STATE_DIR/pacman-aur.txt")" ;;
  esac
  echo ">> package restore done."
}

case "${1:-}" in
  capture)          capture ;;
  restore-packages) restore_packages ;;
  *) echo "usage: $0 {capture|restore-packages}"; exit 1 ;;
esac
