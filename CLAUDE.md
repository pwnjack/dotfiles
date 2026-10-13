# CLAUDE.md

## What this is

Hyprland dotfiles for Arch Linux / CachyOS, self-contained at `~/.config`. Pywal derives a palette from the wallpaper and fans it out to every themed component.

## Key commands

```bash
./install.sh [--dry-run] [--no-backup]   # Fresh install
./doctor.sh                              # Validate live system (exit 1 only on ERROR)
./test.sh [--list]                       # Run every suite

wal -i /path/to/wallpaper.jpg            # New scheme...
~/.config/scripts/theming/apply-wal.sh   # ...fan out to every component
~/.config/hypr/apply_wal_colors.sh       # Re-render Hyprland/Hyprlock palette
hyprctl reload                           # Reload Hyprland config
~/.config/scripts/waybar/waybar.sh       # Reload Waybar (Super+Shift+B)

echo "firefox" > ~/.config/options/browser   # Preferences are plain text files
```

## Architecture

Deep dives live in `docs/internals/`. **Read the matching file before changing a component.**

### Hyprland config (Lua, loaded from `hypr/hyprland.lua`)

`hypr/config/`: `colors.lua`, `colors.conf`, `apptype.lua`, `hardware/{monitor,input}.lua`, `hardware/primary.conf`, `looks/{decor,animations}.lua`, `setup/{envvars,autostart}.lua`, `software/{keybinds,general,rules,workspace_step}.lua`. `colors.conf` and `primary.conf` are Hyprlock-only symlinks to generated state. `hyprland.lua` loads the untracked `overrides.lua` last. Hyprlock, Hypridle and Hyprsunset are separate programs and keep their Hyprlang `.conf` files.

### Pywal colour flow

`wal -i` -> `scripts/theming/apply-wal.sh`; `scripts/hyprland/wall.sh` triggers it on wallpaper change. Generated state lives under `~/.cache`; the repo tracks only symlinks to it. Components needing more than a plain include own `<component>/apply_wal_colors.sh`. The driver **globs** for them: adding one is one new file, with no edit to the driver, `wall.sh` or `install.sh`. Every one must:

1. Render into `~/.cache/wal/` and never write a tracked file.
2. **Always leave its output existing**, falling back to defaults when pywal input is missing (a dangling tracked symlink is a doctor ERROR).
3. Be idempotent, and a no-op when its component is not installed.
4. Reload its own running consumer if possible; the driver knows nothing about `swaync-client` or `SIGUSR2`.

Use `scripts/theming/palette.sh` (`wal_load`, `wal_readable_on`, `wal_oklch`), never re-parse pywal output. Never reload Waybar for a palette. Cava, starship, Vesktop and Zen are templated (`<component>/<name>.in`): **edit the `.in` file, never the symlink.** Read `docs/internals/theming.md` before touching a themed component or `wall.sh`.

### Components

Doc named per item is in `docs/internals/`.

- **Wallpaper carousel** (Super+Ctrl+W): `quickshell/wallpaper-carousel/`, applies through `carousel-apply.sh`, which runs `wall.sh` exactly once. `wallpaper-carousel.md`.
- **Keybindings overlay** (Super+H): `quickshell/keybinds-overlay/`, read-only. `keybinds-overlay.md`.
- **Workspaces** (`waybar/workspaces/`, C): native Waybar CFFI module built by `scripts/waybar/build-workspaces.sh`; `module.c` must export all five `wbcffi_*` functions. `workspaces.md`.
- **Update card** (`quickshell/updates/`): runs root helper `/usr/local/bin/system-update`. `update-card.md`.
- **Calendar** (Super+Shift+E): `scripts/calendar/sync.sh` is the only path to iCloud and `cal.sh` the only khal reader and writer (edits via `ics-edit.py`, adds via `khal import`, never `khal new`). Passwords live only in the keyring and reach tools on stdin, never argv. `options/calendar-*` is untracked. `calendar.md`.
- **Capture bar** (Super+Shift+S / Super+Shift+R): `quickshell/capture/`. `scripts/capture/record.sh` is the only driver of gpu-screen-recorder, `scripts/hyprland/screenshot.sh` the only screenshot command, `scripts/hyprland/lock.sh` the only lock path (locks first, then stops any recording). `capture-bar.md`.
- **Machine state**: settings a machine changes are not tracked. `defaults/` holds the tracked default; the live file (`options/*`, GTK and Qt settings, `mimeapps.list`, `swaync/config.json`, `hypr/hyprsunset.conf`) is rendered and git-ignored; this machine's differences live in `~/.local/state/dotfiles/overrides`. `scripts/state/overlay.sh sync` harvests live edits and re-renders. To change a repo default, edit `defaults/` and commit; never track a live file. Never run the overlay scripts against the real `HOME` from a test or a worktree. `state.md`.
- **Settings panel** (Super+I): `quickshell/settings-panel/`. `catalog.json` is the only list of settings; panel changes land in untracked state, never the repo. Panel writes reach `panel-request.sh -` on stdin, never argv. `settings-panel.md`.
- **Spotify**: `scripts/spotify/launch.sh` re-patches Spotify. SpotX `pkill`s `[sS]potify` by name, so the wrapper's file name must not contain it. `spotify.md`.
- **Night light**: `hypr/hyprsunset.conf` is rendered; edit `defaults/hypr/hyprsunset.conf`, not the live file. `scripts/hyprland/nightlight.sh` is the **only** thing that talks to `hyprctl hyprsunset`; there is no state file. Profiles omit `gamma` (`gamma = 100` makes the daemon exit). `night-light.md`.
- **Virtual surround**: `pipewire/pipewire.conf.d/60-virtual-surround.conf` is the only tracked PipeWire config; not the default output. See `docs/virtual-surround.md`.
- **SDDM greeter sync**: `sddm/watch_wallpaper.sh`; the NOPASSWD target is a root-owned copy of `sddm/update_sddm_root.sh` in `/usr/local/bin`. Never point a sudo rule at a user-writable script; review that source before re-running setup. `sddm.md`.
- **SSH agent**: `scripts/ssh/setup.sh` puts `Include ~/.config/ssh/config` as the **first** line of `~/.ssh/config` and never edits a symlinked one. `ssh-agent.md`.
- **Gaming** (WoW / Battle.net): `docs/gaming-wow.md` is the single source; **read it before touching any game rule.** The Hyprland client is *gamescope*, so `rules.lua` applies every game effect to both match tables.
- **Default applications**: `mimeapps.list`, the `BROWSER`/`TERMINAL`/`EDITOR`/`VISUAL` variables exported from `options/` by `envvars.lua`, `xdg-terminal-exec` (`scripts/settings/terminal.sh`) and D-Bus `FileManager1` (`scripts/settings/file-manager.sh`), one source each. `default-apps.md`.
- **User preferences** (`options/`): rendered copy (defaults in `defaults/options/`); one value per file, used as-is. Empty means "no preference" only for `mainmonitor` and `bar-output`; switches are on only when the file says `enabled`. Nothing guesses a monitor connector name; `hardware/monitor.lua` stays host-neutral. `options.md`.

### AI agent harness (`claude/`, `codex/`)

`claude/` and `codex/` track only what was authored here: the `delegate` skill, the global instructions (`claude/CLAUDE.global.md`, `codex/AGENTS.global.md`) and curated settings — never logins, memory, caches or tool-written config. `scripts/agents/setup.sh` wires it in. Read `docs/internals/agents.md` before changing any of it.

### Scripts (`scripts/`)

Bash; check for command existence before running; read preferences from `options/`. One concern per directory (`docs/internals/scripts.md`).

### API keys

`~/.config/.env` (git-ignored; template `.env.example`), loaded by Fish and `scripts/hyprland/launch-chatbox.sh`. Keys: `GEMINI_`, `OPENAI_`, `ANTHROPIC_`, `GROQ_`, `MISTRAL_API_KEY`.

## Core stack

| Role | Tool |
|------|------|
| WM | Hyprland (Wayland) |
| Bar | Waybar |
| Launcher | Rofi |
| Terminal | Ghostty |
| Notifications | SwayNC (toast + sidebar) |
| Shell | Fish + Starship |
| Editor | Neovim (LazyVim) |
| Theming | Pywal + GTK3/4 + Qt5/6 + Kvantum |

## Conventions

- Every window and workspace bind carries `Super`. On arrows: `Super` focuses, `+ Shift` moves, `+ Alt` resizes, `+ Ctrl` switches workspace. Keep new nav binds on it.
- `.gitignore` is a whitelist: tracking a new config means adding its `!/<entry>` line. Never track what a program writes itself (app state, lock files, caches).
- `scripts/keybinds/keybinds-sheet.sh` is the one parser of `keybinds.lua`; never hand-write rows. Each one-line `hl.bind(...)` carries a trailing `--` label; `tst_Overlay` fails if the overlay would elide it, so shorten the label.
- `docs/keybindings.md` is **generated** by `scripts/docs/generate-keybindings.sh`: never hand-edit it, and regenerate after touching `keybinds.lua`. `scripts/lib/hypr-vars.sh` owns which variables stay unresolved; do not restate that list.
- Doctor checks derive every target from tracked files; never hand-write a list of paths, binaries or packages.
- Check modules never run loops in a pipeline (`cmd | while read`): use `while read ...; do ... done < <(cmd)`. The harness fails the suite on it.
- Use `git ls-files -z` with `while IFS= read -r -d ''`, never plain `git ls-files`.
- `scripts/doctor/` and `docs/` are excluded from the doctor's literal-path scan.
- `./test.sh` discovers suites: a tracked `run-tests.sh`, or a `test-*.sh` in a directory with none, is an entry point; naming a file that way is the whole of adding one.
- `scripts/hooks/pre-commit` passes staged paths to `test.sh --for` and runs checks in a snapshot of the staged tree, never against unstaged files.

## Doctor architecture (`scripts/doctor/`)

`doctor.sh` sources `scripts/doctor/lib.sh` and one `checks/<name>.sh` per concern. Each module exposes one public `check_<name>` plus prefixed private helpers, and every host probe sits in its own tiny function so tests can stub it. `ok` is printed only when a check found nothing at all, and every path in a fix hint goes through `doctor_q`. Module tree, helper prefixes and reserved names: `docs/internals/doctor.md`; read it before adding or changing a check.
