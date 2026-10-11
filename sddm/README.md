# SDDM wallpaper sync

Scripts that keep the SDDM login screen background in sync with your desktop wallpaper.

## Files

| File | Purpose |
|------|---------|
| `watch_wallpaper.sh` | Watches for awww wallpaper changes (started via Hyprland autostart) |
| `update_sddm.sh` | User-side updater; delegates to the installed root-owned helper via sudo |
| `update_sddm_root.sh` | Tracked source for the privileged helper; decodes as the target user, then atomically installs the SDDM theme background as root |
| `setup-sudo.sh` | Installs or upgrades the root-owned helper and its passwordless-sudo rule |

## Setup

### 1. Configure passwordless sudo (required for automatic sync)

```bash
~/.config/sddm/setup-sudo.sh
```

This installs `sddm-wallpaper-update` as a root-owned, mode-0755 helper in
`/usr/local/bin`, then installs a sudoers drop-in allowing your user to run that
helper as root without a password only when its sole argument is your exact
username. Re-run the setup command after changing `update_sddm_root.sh`; it
upgrades the installed copy when the tracked source has changed.

The automatic passwordless path closes one specific escalation path: it runs
the root-owned installed copy, not a user-writable script in `$HOME`. The manual
installation path does not close that boundary. `setup-sudo.sh` installs from
`$SCRIPT_DIR/update_sddm_root.sh`, which is user-writable here, so anything able
to change that source gains root execution the next time the user runs setup.

The helper still runs as root because it must write
`Backgrounds/wallpaper.jpg`, but wallpaper discovery and `ffmpeg` decoding run
as the target user. Root creates a temporary output in the theme's
`Backgrounds` directory and atomically renames it only after a successful
decode, so a failed conversion preserves the existing greeter image. The
resolved theme and `Backgrounds` directories must remain root-owned; otherwise
an unprivileged user could substitute the temporary or destination path used
by the privileged rename.

### 2. Test it

```bash
~/.config/sddm/update_sddm.sh
```

Run `~/.config/doctor.sh` at any time to check the effective sudo grant, helper
installation and drift, theme-directory ownership, ffmpeg, watcher process,
and whether the greeter image is older than the newest awww cache trigger.

## How it works

1. **On wallpaper change**: `watch_wallpaper.sh` (started via Hyprland autostart)
   notices the awww cache update and runs `update_sddm.sh`.
2. **Wallpaper detection**: the helper, running as the target user, reads the
   awww cache (`~/.cache/awww/<version>/<monitor>`), falling back to the
   `~/.config/options/wallpaper` symlink.
3. **Conversion**: `ffmpeg` decodes the image as the target user and streams a
   JPEG to a root-created temporary file for the theme configured in
   `/etc/sddm.conf` (default `sddm-astronaut-theme`, which is also updated
   whenever it is installed). Root then atomically renames that file to
   `/usr/share/sddm/themes/<theme>/Backgrounds/wallpaper.jpg`.

## Troubleshooting

- **Wallpaper not updating**: run `~/.config/doctor.sh`; then apply its setup or watcher fix
- **ffmpeg not found**: install it with `sudo pacman -S ffmpeg`
- **Wrong theme updated**: check the `Current=` value under `[Theme]` in `/etc/sddm.conf`
