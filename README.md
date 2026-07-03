<p align="center">
  <img src="assets/icon-256.png" width="120" alt="beaver" />
</p>

# beaver

Reproducible **backup & restore** for Linux workstations — captures declarative
system state and home/user data, and pushes it to multiple destinations with
[restic](https://restic.net) (dedup, incremental, encrypted).

**Tested distros:** [Bazzite](https://bazzite.gg) (Fedora atomic / rpm-ostree)
and [CachyOS](https://cachyos.org) (Arch). They rebuild differently, so state
capture/restore is per-distro; data backup is shared.

> **Public repo:** no hosts, paths, or secrets are committed. All of that lives
> in an untracked `config.env` (copy from `config.env.example`).

## What it captures

- **System state (declarative)** → rebuild the OS without a full image:
  - Bazzite: booted image ref, `rpm-ostree` layered packages, Flatpak app list, enabled units
  - CachyOS: explicit native pkgs (`pacman -Qqen`), AUR pkgs (`pacman -Qqem`), Flatpak list, enabled units
- **Home / user data** → `~` via restic, with sensible excludes (caches, Steam
  game installs, Heroic games — re-downloadable).

## Destinations (any combination)

- **Homelab NAS** (e.g. unraid over SFTP/REST)
- **External drive**
- **Cloud** (S3 / Backblaze B2)

Each is a restic repository; `backup.sh` writes to every one that's configured.

## Quick start

```bash
git clone https://github.com/argyle-labs/beaver.git
cd beaver
./bootstrap.sh                      # install restic + deps for your distro
cp config.env.example config.env    # then edit: destinations, excludes, creds
chmod 600 config.env

./backup.sh                         # capture state + back up to all configured targets
./backup.sh --state-only            # just refresh the system-state manifest
./restore.sh --target nas           # restore data from a target (interactive)
./restore.sh --packages             # reinstall packages from the captured manifest
```

## Verify your backups

A backup you never check is a guess. `check.sh` verifies the setup is healthy —
the encryption key exists (and is `600`), every configured repo is reachable,
the newest snapshot isn't stale, and the state manifest is fresh:

```bash
./check.sh              # human-readable report (read-only, never writes a repo)
./check.sh --verify     # also run `restic check` (repo-structure integrity)
./check.sh --json       # machine-readable issues (shape mirrors orca's Issue type)
./check.sh --notify     # push a WARN/CRIT summary to NTFY_URL (see config.env)
```

Exit code: `0` all-OK, `1` any WARN, `2` any CRIT. Age thresholds
(`MAX_SNAPSHOT_AGE_DAYS`, `MAX_STATE_AGE_DAYS`) and `NTFY_URL` live in `config.env`.

Automate with the included systemd timers:

```bash
./bootstrap.sh --timer              # enables a daily backup timer + a daily
                                    # health-check timer (check.sh --notify)
```

## Restore a machine from scratch

1. Install the base OS (Bazzite or CachyOS), clone this repo, `./bootstrap.sh`.
2. `cp config.env.example config.env` and point it at the destination that has
   your backups (+ supply the restic password / cloud creds).
3. `./restore.sh --packages` — rehydrates Flatpaks + layered/pacman packages from
   the manifest.
4. `./restore.sh --target <nas|extdrive|cloud>` — restores `~` data.
5. Reboot (Bazzite: after `rpm-ostree` changes).
6. `./check.sh --verify` — confirm the repos you restored from are healthy.

See [docs/NOTES.md](docs/NOTES.md) for per-distro gotchas.

## Orca integration (planned)

These scripts use clean subcommands (`backup.sh`, `restore.sh`,
`lib/state.sh capture|restore`) specifically so they can be wrapped as an **orca
plugin** later. Keep that contract stable.

## License

MIT — see [LICENSE](LICENSE).
