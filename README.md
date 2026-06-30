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

Automate with the included systemd timer:

```bash
./bootstrap.sh --timer              # installs + enables a daily user timer
```

## Restore a machine from scratch

1. Install the base OS (Bazzite or CachyOS), clone this repo, `./bootstrap.sh`.
2. `cp config.env.example config.env` and point it at the destination that has
   your backups (+ supply the restic password / cloud creds).
3. `./restore.sh --packages` — rehydrates Flatpaks + layered/pacman packages from
   the manifest.
4. `./restore.sh --target <nas|extdrive|cloud>` — restores `~` data.
5. Reboot (Bazzite: after `rpm-ostree` changes).

See [docs/NOTES.md](docs/NOTES.md) for per-distro gotchas.

## Orca integration (planned)

These scripts use clean subcommands (`backup.sh`, `restore.sh`,
`lib/state.sh capture|restore`) specifically so they can be wrapped as an **orca
plugin** later. Keep that contract stable.

## License

MIT — see [LICENSE](LICENSE).
