# Field Notes & Gotchas — backup/restore

## Bazzite (Fedora atomic / rpm-ostree)
- The OS image itself is reproducible — you don't back up `/usr`. Capture the
  **booted image ref** (`image-ref.txt`) and **layered packages**
  (`rpm-ostree status --json` → `requested-packages`); restore = rebase to the
  image + `rpm-ostree install` the layers, then reboot.
- Most apps are **Flatpaks** — `flatpak list --app` is the real package manifest.
  Flatpak *data* lives under `~/.var/app/<id>` and is covered by the home backup
  (exclude the per-app `cache` dirs).
- Layering/restoring packages needs `sudo rpm-ostree` and a **reboot** to apply.
- `/etc` is a writable overlay; only your own edits matter — capture selectively
  if needed (not done by default).

## CachyOS (Arch)
- Two package lists: `pacman -Qqen` (explicit native/repo) and `pacman -Qqem`
  (explicit foreign/AUR). Restore native with `pacman -S --needed -`; AUR needs a
  helper (paru/yay) — the script lists them rather than guessing your helper.
- CachyOS uses btrfs; if you also want **local snapshots** for instant rollback,
  pair this with snapper/timeshift (not in scope here — we do off-box restic).

## restic / destinations
- One **password file** unlocks all repos (`RESTIC_PASSWORD_FILE`). Back that key
  up somewhere safe and OFFLINE — without it the backups are unrecoverable.
- `backup.sh` writes to every configured target independently; one failing target
  doesn't stop the others (exit code reflects any failure).
- **NAS over SFTP** needs key-based SSH to the NAS. **REST server** (`rest:`) is
  faster for many small files. **Cloud** (S3/B2) needs the creds exported (keep
  them in `config.env`, which is gitignored).
- Restore lands under `--path` (default `/`); to restore into your home use
  `--path "$HOME"` and pick the snapshot with `--snapshot <id>`.

## General
- `config.env` is **gitignored** — this is a public repo. Never commit hosts,
  paths, or cloud creds.
- The home backup excludes re-downloadable bulk (Steam `steamapps`, `~/Games`,
  caches). Game *saves* in `~/.var/app`, `~/.local/share`, and prefixes are kept.
- Test restores periodically — a backup you've never restored is a guess.
