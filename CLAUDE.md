# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Hyprland dotfiles repository for Arch Linux / CachyOS. The entire repo lives at `~/.config` and is self-contained — all scripts, wallpapers, and user preferences are within this directory. Dynamic colour theming is driven by pywal, which generates a 16-colour palette from the active wallpaper and propagates it to Hyprland, Hyprlock, Waybar, Rofi, SwayNC, the terminal and its TUI apps, Neovim, and a few GUI apps (see Pywal colour flow).

## Key commands

```bash
# Install on fresh system (interactive, checks deps via pacman/paru)
./install.sh              # Full install
./install.sh --dry-run    # Preview without changes
./install.sh --no-backup  # Skip config backup

# Validate the live system (report-only; exits 1 only on ERROR findings)
./doctor.sh

# Run every test suite in the repo (or --list to see which ones exist)
./test.sh

# Apply a new colour scheme from a wallpaper, then fan it out to every component
wal -i /path/to/wallpaper.jpg
~/.config/scripts/theming/apply-wal.sh

# Re-render Hyprland and Hyprlock palette files
~/.config/hypr/apply_wal_colors.sh

# Reload Hyprland config
hyprctl reload

# Reload Waybar, or start it with its includes rendered (Super+Shift+B)
~/.config/scripts/waybar/waybar.sh

# Change user preferences (plain text files)
echo "firefox" > ~/.config/options/browser
echo "ghostty" > ~/.config/options/terminal
```

## Architecture

Component deep dives live in `docs/internals/`; each section below keeps only the rules that apply to every edit. **Read the matching file before changing that component.**

### Hyprland config (modular Lua, loaded from `hypr/hyprland.lua`)

```
hypr/config/
├── colors.lua               # Symlink -> ~/.cache/wal/colors-hyprland.lua
├── colors.conf              # Hyprlock-only symlink -> cached Hyprlang palette
├── apptype.lua              # Default app definitions
├── hardware/
│   ├── monitor.lua          # Display resolution/layout
│   ├── input.lua            # Keyboard/mouse settings
│   └── primary.conf         # Hyprlock-only symlink -> ~/.local/state/hypr/primary.conf
├── looks/
│   ├── decor.lua            # Borders, blur, rounding
│   └── animations.lua       # Window animations
├── setup/
│   ├── envvars.lua          # Environment variables
│   └── autostart.lua        # hyprland.start applications
└── software/
    ├── keybinds.lua         # All keyboard shortcuts
    ├── general.lua          # Misc settings
    ├── rules.lua            # Window and layer rules
    └── workspace_step.lua   # Super+Ctrl+arrow stepping, bounded to the dot row
```

Beside `config/`, `hypr/` holds `hyprland.lua` (the entry point, which also
loads the panel's untracked `overrides.lua` last), `apply_wal_colors.sh`,
`hypridle.conf`, `hyprlock.conf`, the rendered `hyprsunset.conf` (untracked) and `test/`.

Hyprland's config is Lua. Hyprlock, Hypridle, and Hyprsunset are separate
programs and intentionally keep their Hyprlang `.conf` files.

### Pywal colour flow

Wallpaper image -> `wal -i` -> `scripts/theming/apply-wal.sh` fans the palette out to every consumer. `scripts/hyprland/wall.sh` (wallpaper changes) triggers it automatically. Generated state lives under `~/.cache`; the repo tracks only symlinks to it, so wallpaper switches never dirty git.

Components that need more than a plain include own a `<component>/apply_wal_colors.sh`. The driver **globs** for them, so adding a themed component is one new file and no edit to the driver, `wall.sh` or `install.sh`. Every `apply_wal_colors.sh` must:

1. Render into `~/.cache/wal/` and never write a tracked file.
2. **Always leave its output existing**, falling back to defaults when the pywal input is missing. The repo tracks a symlink to that output, and a dangling tracked symlink is an ERROR in `doctor.sh` (a fresh checkout has an empty cache).
3. Be idempotent, and a no-op when its component is not installed.
4. Reload its own running consumer if that is possible. The driver knows nothing about `swaync-client` or `SIGUSR2`.

`scripts/theming/palette.sh` is the shared loader (`wal_load`, `wal_readable_on`, `wal_oklch`); use it instead of re-parsing pywal output, because a wallpaper palette gives no contrast guarantees. Waybar is never reloaded for a new palette (`reload_style_on_change` restyles it in place; a reload resizes every tiled window).

Four components are templated (`<component>/<name>.in` -> rendered to cache -> a symlink to it): cava, starship, Vesktop and Zen. **Edit the `.in` file, never the symlink.** Why each component is wired the way it is (cava's heap bug, Ghostty OSC resets, Neovim sockets, Vesktop/Zen/Spicetify clamps, `wall.sh` staging and locking): `docs/internals/theming.md`. Read it before touching a themed component or `wall.sh`.

### Wallpaper carousel

`quickshell/wallpaper-carousel/` is an on-demand Quickshell app opened by `scripts/hyprland/wallpaper-carousel.sh` (Super+Ctrl+W); it applies through `carousel-apply.sh`, which runs `wall.sh` exactly once. Internals: `docs/internals/wallpaper-carousel.md` (and `docs/wallpaper-carousel.md` for checks and measurements).

### Keybindings overlay (Super+H)

`quickshell/keybinds-overlay/` is a read-only HUD fed by `scripts/keybinds/keybinds-sheet.sh --json` on every open. Internals: `docs/internals/keybinds-overlay.md`, `docs/keybinds-overlay.md`.

### Workspace module (cffi/workspaces)

The workspace dots are one native Waybar CFFI module in `waybar/workspaces/` (C), built out of tree by `scripts/waybar/build-workspaces.sh`; `doctor.sh` checks the build is current and `scripts/hooks/post-merge` rebuilds after a pull. `module.c` must export all five `wbcffi_*` functions. Internals and the way back to the CSS dots: `docs/internals/workspaces.md`, `docs/workspaces-native.md`.

### Update card (Waybar custom/updates)

`quickshell/updates/` is the on-demand update card started by `scripts/hyprland/updates-popover.sh`; it runs the root helper `/usr/local/bin/system-update` (installed by `updates/setup-sudo.sh`, one NOPASSWD rule). Internals: `docs/internals/update-card.md`, `docs/updates.md`.

### Calendar (clock capsule, Super+Shift+E)

`scripts/calendar/sync.sh` is the only path to iCloud and `cal.sh` the only khal reader and writer (edits go through `ics-edit.py`, adds through `khal import`, never `khal new`). Passwords live only in the keyring and reach tools on stdin, never in argv. `options/calendar-*` is untracked (calendar names are personal). Internals: `docs/internals/calendar.md`, `docs/calendar.md`.

### Capture bar (Super+Shift+S / Super+Shift+R)

`quickshell/capture/` is the on-demand screenshot/recording strip. `scripts/capture/record.sh` is the only driver of gpu-screen-recorder, `screenshot.sh` the only screenshot command, and `scripts/hyprland/lock.sh` the only lock path (it locks first, then stops any recording). Internals: `docs/internals/capture-bar.md`, `docs/capture.md`.

### Machine state (overlay)

Settings a machine changes are not tracked: `defaults/` holds the tracked default of each, the live file at the same path (`options/*`, GTK and Qt settings, `mimeapps.list`, `swaync/config.json`, `hypr/hyprsunset.conf`) is rendered and git-ignored, and this machine's differences live in `~/.local/state/dotfiles/overrides`. `scripts/state/overlay.sh sync` harvests live edits into overrides and re-renders; it runs at login (in the background), after a pull (`post-merge`), on install (`--replace`) and after panel writes to rendered files. To change a repo default, edit `defaults/` and commit; never track a live file. Never run the overlay scripts against the real `HOME` from a test or a worktree. Details: `docs/internals/state.md`.

### Settings panel (Super+I)

`quickshell/settings-panel/` starts on demand via `scripts/hyprland/settings-panel.sh`. `catalog.json` is the only list of settings; panel changes land in untracked state (machine overlay, `~/.local/state/hypr/overrides.lua`, `monitors.lua`) so using the panel never dirties the repo. Panel writes reach `panel-request.sh -` on stdin, never in argv. Internals: `docs/internals/settings-panel.md`, `docs/settings-panel.md`.

### Spotify (SpotX)

`scripts/spotify/launch.sh` starts Spotify and re-patches it (SpotX, then Spicetify) after each client update; the running-Spotify check happens under the lock, and SpotX `pkill`s `[sS]potify` by name, so the wrapper's file name must not contain it. Internals: `docs/internals/spotify.md`, `docs/spotify.md`.

### Night light (hyprsunset)

`hypr/hyprsunset.conf` is rendered from `defaults/hypr/hyprsunset.conf` plus the machine's `$variables`; edit the default, not the live file. `scripts/hyprland/nightlight.sh` is the **only** thing that talks to `hyprctl hyprsunset`, and there is deliberately no state file (the daemon is the state). A profile `gamma` is a multiplier, not a percentage: `gamma = 100` makes the daemon exit, so profiles omit it. Other probed gotchas (no `identity` getter, no working `--config`, stale sockets, icon names in the panel versus notifications): `docs/internals/night-light.md`.

### Virtual surround (PipeWire)

`pipewire/pipewire.conf.d/60-virtual-surround.conf` is the only tracked PipeWire
config: a filter-chain sink, *Virtual Surround 7.1 (headphones)*, that renders 8
channels binaurally through libmysofa's KEMAR HRTF into stereo. It is chosen per
application and is not meant to be the default output; its output follows the
default sink and names no device. See `docs/virtual-surround.md`.

### SDDM greeter wallpaper sync

`sddm/watch_wallpaper.sh` keeps the greeter background in step with awww. The NOPASSWD target is a root-owned copy of `sddm/update_sddm_root.sh` under `/usr/local/bin`; never point a sudo rule at a user-writable script, and review changes to that source before re-running setup. Details: `docs/internals/sddm.md`.

### SSH agent

OpenSSH's packaged `ssh-agent.socket` holds the key; `SSH_AUTH_SOCK` is set in `hypr/config/setup/envvars.lua`, and `scripts/ssh/setup.sh` puts `Include ~/.config/ssh/config` as the **first** line of `~/.ssh/config` (a later line would apply to one `Host` block only). It never edits a symlinked `~/.ssh/config`. Details: `docs/internals/ssh-agent.md`.

### Gaming (WoW / Battle.net)

`docs/gaming-wow.md` is the single source for this — **read it before touching
any game rule.** The current launch chain is Rofi -> Lutris -> gamescope ->
Battle.net -> WoW, so the Hyprland client is *gamescope*, not the game, and
`rules.lua` applies every game effect to both match tables for that reason.
The launcher settings are machine-local (Lutris under `~/.local/share/lutris`,
with a separate Faugus entry retained). The doc records the current Lutris
baseline and the historical Faugus recipe as prose — including which flag
fixed what, and which tuning ideas were measured and rejected (gamemode buys
`nice -4` here and nothing else). Don't re-derive that survey.

### Default applications

Four mechanisms, one source each: `mimeapps.list` (default tracked in `defaults/`, this machine's copy rendered and written by the panel through `xdg-mime`), the `BROWSER`/`TERMINAL`/`EDITOR`/`VISUAL` variables exported from `options/` by `envvars.lua`, `xdg-terminal-exec` (via `scripts/settings/terminal.sh`) and D-Bus `FileManager1` (`scripts/settings/file-manager.sh`). Nothing in `~/.profile` is needed. Details: `docs/internals/default-apps.md`.

### User preferences (`options/`)

`options/` is this machine's rendered copy (defaults in `defaults/options/`; see Machine state). `echo x > options/key` still works; the next sync records it. It holds one value per text file that scripts read directly (`cat` or `read -r`) and use as-is: `browser`, `terminal`, `editor`, `font`, `aurhelper`, the `bar-*`, `capture-*` and `calendar-*` settings and more (full list: `docs/internals/options.md`). Empty means "no preference" only for `mainmonitor` and `bar-output`; switches are on only when the file says `enabled`. Nothing guesses a monitor connector name, and `hardware/monitor.lua` stays host-neutral (per-machine rules live in the untracked `~/.local/state/hypr/monitors.lua`).

### AI agent harness (`claude/`, `codex/`)

The repo tracks only what was authored here for Claude Code and Codex: the
delegation skills (`claude/skills/`, with `_shared/handoff.md` for running a
worker and `_shared/review.md` for reviews as the contracts, and
`test-codex-model.sh` and `test-skills.sh` as their suites), one hook, the global instructions
(`claude/CLAUDE.global.md`, `codex/AGENTS.global.md` — named so neither is
auto-loaded as a nested project file), and curated settings. Logins, history,
memory, caches, plugin checkouts and anything a tool writes into its own config
(Herdr's agent-state hooks, project trust entries, auto-mode text) are never
tracked, so a fresh machine stays fresh and the public repo carries no machine
state. `scripts/agents/setup.sh` wires it in and skips any tool that is absent:
it symlinks each skill directory, the hook and the global instructions, runs
`claude/apply-settings.sh` and `codex/apply-config.sh`, installs the Claude
plugins the tracked settings list, and lets `herdr integration install` own the
Herdr hooks. `install.sh` calls it.

Neither live settings file is a symlink, because the tools rewrite them.
`claude/apply-settings.sh` merges `claude/settings.json` into
`~/.claude/settings.json` (objects key by key; a tracked hook group replaces any
live group running the same script file). `codex/apply-config.sh` merges every
`codex/*.toml` fragment into `~/.codex/config.toml` key by key — single-line
values only. Edit the tracked file, then run the script. `claude/statusline.sh`
is the Claude Code status line.

### Scripts (`scripts/`)

Scripts are bash (plus a few Node modules in `updates/` and Python in `calendar/`), check for command existence before running, and read preferences from `options/`. Each directory under `scripts/` owns one concern: `hyprland/` (session and desktop), `waybar/`, `devices/`, `calendar/`, `capture/`, `updates/`, `settings/`, `theming/`, `fonts/`, `spotify/`, `ssh/`, `agents/`, `keybinds/`, `docs/`, `doctor/`, `hooks/`, `lib/`. The per-directory notes (the battery module's `SCOPE` rules, the media player picker) are in `docs/internals/scripts.md`.

### API keys

Stored in `~/.config/.env` (git-ignored). Template at `.env.example`. Loaded by Fish on startup and by the AI sidebar launcher (`scripts/hyprland/launch-chatbox.sh`). Supports: `GEMINI_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GROQ_API_KEY`, `MISTRAL_API_KEY`.

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

- The repo migrated from `~/Dots` to `~/.config` (Jan 2026). There should be no remaining references to `~/Dots`.
- Config is Arch/CachyOS-specific — package management uses `pacman` and `paru`/`yay` for AUR.
- Every window and workspace keybinding carries `Super`, so `Alt`/`Ctrl` + arrows stay free for apps (browser back/forward, shell word jumps, TUI prompts). On the arrows: `Super` focuses, `+ Shift` moves, `+ Alt` resizes, `+ Ctrl` switches workspace. Keep new navigation binds on that grammar.
- `.gitignore` is a whitelist: `/*` ignores everything in `~/.config`, then one `!/<entry>` line per tracked top-level file or directory, then the runtime files inside those directories. A new app is therefore ignored with no edit; tracking a new config means adding its `!` line. Never track what a program writes itself (app state, lock files, caches).
- `scripts/keybinds/keybinds-sheet.sh` is the one parser of `keybinds.lua` (it feeds the Super+H overlay and `docs/keybindings.md`); never hand-write rows. Each one-line `hl.bind(...)` carries a trailing `--` label, and `tst_Overlay` fails if the overlay would elide it, so shorten the label rather than the type. Details: `docs/internals/conventions.md`.
- `docs/keybindings.md` is **generated** by `scripts/docs/generate-keybindings.sh`: never hand-edit it, and regenerate after touching `keybinds.lua` (`test/test-docs.sh` fails on a stale copy). `scripts/lib/hypr-vars.sh` owns which variables stay unresolved; do not restate that list. The README keeps only the five essential binds. Details: `docs/internals/conventions.md`.
- `doctor.sh` and its check modules derive every target from tracked files. When adding a check, never introduce a hand-written list of paths, binaries, or packages — parse the config that already declares them. A list is a second source of truth and will drift.
- Check modules must never run their loops in a pipeline (`cmd | while read`); the severity counters are shell variables and would be lost in the subshell, silently discarding every finding. Use `while read ...; do ... done < <(cmd)`. The test harness greps for this and fails the suite.
- Use `git ls-files -z` with `while IFS= read -r -d ''`, never plain `git ls-files` — git C-quotes paths containing non-ASCII or quote characters, and the quoted form names no file on disk.
- `scripts/doctor/` and `docs/` are excluded from the doctor's literal-path scan: both deliberately contain example paths that do not exist.
- `./test.sh` discovers suites: a tracked `run-tests.sh`, or a `test-*.sh` in a directory with none, is an entry point, and naming a new file that way is the whole of adding one. Each suite runs as `bash <path>` and its exit code is the only contract. Details: `docs/internals/conventions.md`.
- `scripts/hooks/pre-commit` passes the staged paths to `test.sh --for` and runs its checks in a snapshot of the staged tree, never against unstaged working files. Details: `docs/internals/conventions.md`.

## Doctor architecture (`scripts/doctor/`)

`doctor.sh` sources `scripts/doctor/lib.sh` and one `checks/<name>.sh` per concern. Each module exposes one public `check_<name>` function plus prefixed private helpers, and every host probe (`pgrep`, `pacman`, `/sys/class/drm`, ...) sits in its own tiny function so tests can stub it. Targets are always derived from tracked files, never hand-listed. `ok` is printed only when a check found nothing at all, and every path in a fix hint goes through `doctor_q`. The full module tree, helper prefixes and reserved names: `docs/internals/doctor.md`. Read it before adding or changing a check.
