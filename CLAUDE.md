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
│   └── primary.conf         # Hyprlock-only monitor variable
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
`hypridle.conf`, `hyprlock.conf`, `hyprsunset.conf` and `test/`.

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

### Settings panel (Super+I)

`quickshell/settings-panel/` starts on demand via `scripts/hyprland/settings-panel.sh`. `catalog.json` is the only list of settings; panel changes land in untracked state (`~/.local/state/hypr/overrides.lua`, `monitors.lua`) so using the panel never dirties the repo. Panel writes reach `panel-request.sh -` on stdin, never in argv. Internals: `docs/internals/settings-panel.md`, `docs/settings-panel.md`.

### Spotify (SpotX)

`scripts/spotify/launch.sh` starts Spotify and re-patches it (SpotX, then Spicetify) after each client update; the running-Spotify check happens under the lock, and SpotX `pkill`s `[sS]potify` by name, so the wrapper's file name must not contain it. Internals: `docs/internals/spotify.md`, `docs/spotify.md`.

### Night light (hyprsunset)

`scripts/hyprland/nightlight.sh` is the **only** thing that talks to `hyprctl hyprsunset`, and there is deliberately no state file (the daemon is the state). A profile `gamma` is a multiplier, not a percentage: `gamma = 100` makes the daemon exit, so profiles omit it. Other probed gotchas (no `identity` getter, no working `--config`, stale sockets, icon names in the panel versus notifications): `docs/internals/night-light.md`.

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

Four mechanisms, one source each: `mimeapps.list` (tracked, written by the panel through `xdg-mime`), the `BROWSER`/`TERMINAL`/`EDITOR`/`VISUAL` variables exported from `options/` by `envvars.lua`, `xdg-terminal-exec` (via `scripts/settings/terminal.sh`) and D-Bus `FileManager1` (`scripts/settings/file-manager.sh`). Nothing in `~/.profile` is needed. Details: `docs/internals/default-apps.md`.

### User preferences (`options/`)

`options/` holds one value per text file that scripts read directly (`cat` or `read -r`) and use as-is: `browser`, `terminal`, `editor`, `font`, `aurhelper`, the `bar-*`, `capture-*` and `calendar-*` settings and more (full list: `docs/internals/options.md`). Empty means "no preference" only for `mainmonitor` and `bar-output`; switches are on only when the file says `enabled`. Nothing guesses a monitor connector name, and `hardware/monitor.lua` stays host-neutral (per-machine rules live in the untracked `~/.local/state/hypr/monitors.lua`).

### AI agent harness (`claude/`, `codex/`)

The repo tracks only what was authored here for Claude Code and Codex: the
delegation skills (`claude/skills/`, with `_shared/handoff.md` as the contract
and `test-codex-model.sh` as its suite), one hook, the global instructions
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
- `scripts/keybinds/keybinds-sheet.sh` is the one parse of `keybinds.lua`: `--json` feeds the Super+H overlay, `--markdown` feeds `docs/keybindings.md`, and `--print` is a terminal preview. Never hand-write rows. Each one-line `hl.bind(...)` has a trailing `--` label (`$vars` inside are resolved); `tst_Overlay` (run on every commit by `test/test-docs.sh`) fails if any real label is elided at 1366×768, 1920×1080, 2560×1440 or portrait 1080×1920, so shorten a label rather than shrinking the type. Media, mouse and wheel keys print their legend (`Volume Up`, `Left button`, `Wheel`); that display table is `_key_display`.
- `docs/keybindings.md` is **generated** by `scripts/docs/generate-keybindings.sh` from that same parser's `--markdown` mode — never hand-edit it, and regenerate after touching `keybinds.lua`. `test/test-docs.sh` fails on a stale copy, and since it lives in `test/` it runs on every commit. The skins differ in exactly one way: markdown does **not** resolve the options-backed `$terminal`/`$browser`, printing `options/terminal` instead, because a committed file must not freeze one machine's preference as though it were fixed. `scripts/lib/hypr-vars.sh` owns which variables those are (`hypr_var_origin`); do not restate that list anywhere else. README keeps only the five essential binds and links here — it carried the full table by hand once and it drifted.
- `doctor.sh` and its check modules derive every target from tracked files. When adding a check, never introduce a hand-written list of paths, binaries, or packages — parse the config that already declares them. A list is a second source of truth and will drift.
- Check modules must never run their loops in a pipeline (`cmd | while read`); the severity counters are shell variables and would be lost in the subshell, silently discarding every finding. Use `while read ...; do ... done < <(cmd)`. The test harness greps for this and fails the suite.
- Use `git ls-files -z` with `while IFS= read -r -d ''`, never plain `git ls-files` — git C-quotes paths containing non-ASCII or quote characters, and the quoted form names no file on disk.
- `scripts/doctor/` and `docs/` are excluded from the doctor's literal-path scan: both deliberately contain example paths that do not exist.
- `./test.sh` discovers suites rather than listing them: a tracked file is an entry point if it is named `run-tests.sh`, or matches `test-*.sh` and its directory has no `run-tests.sh`. Name a new suite either way and it is picked up — by the runner and by the pre-commit hook — with no registration step. A suite's *owning directory* is its own directory minus a trailing `test/` component, and that is what decides which commits run it; a top-level `test/` maps to the whole repo, which is why `test/test-runner.sh` runs on every commit. Each suite is run as `bash <path>` in its own subshell and the only contract is its exit code, so a sourced-fragment harness and a standalone script coexist unchanged.
- `scripts/hooks/pre-commit` decides nothing about which suites to run — it passes the staged paths to `test.sh --for`. It builds two staged listings on purpose: `--diff-filter=ACM` for shellcheck (a deleted file cannot be linted) and an unfiltered one for suite selection (a deletion is exactly when a suite most needs to run). Both use `--no-renames`, or git's single `R` record hides one of the two paths. `scripts/hooks/snapshot.sh` exports both listings and the staged contents from a copied index. All checks run in that temporary tree with private Git metadata and blobs (no commit history), never against unstaged working files or a shared writable object store.

## Doctor architecture (`scripts/doctor/`)

```
doctor.sh                    # Entry point: sources lib + modules, guards the repo, exits 1 on ERROR
scripts/doctor/
├── lib.sh                   # group/ok/err/warn/note/summary, counters, doctor_q, doctor_require_repo
├── checks/                  # Run in this order by doctor.sh
│   ├── symlinks.sh          # check_symlinks   — from `git ls-files -s` mode 120000
│   ├── references.sh        # check_references — from Lua require(), Hyprlang source, literal paths
│   ├── binaries.sh          # check_binaries   — from Lua keybind/autostart hl.exec_cmd() calls
│   ├── services.sh          # check_services   — from autostart daemons, D-Bus roles, install.sh arrays
│   ├── sddm.sh              # check_sddm       — from sddm/setup-sudo.sh and the live SDDM configuration
│   ├── updates.sh           # check_updates    — from updates/setup-sudo.sh and sudo -l
│   ├── waybar.sh            # check_waybar     — from config.jsonc's modules-* arrays and handler values
│   ├── workspaces.sh        # check_workspaces — placed cffi/* modules: library present and current
│   ├── hyprctl.sh           # check_hyprctl    — removed runtime CLI forms under the Lua provider
│   ├── hardware.sh          # check_hardware   — /sys/class/drm present set vs tracked files
│   ├── autostart.sh         # check_autostart  — per-user XDG autostart entries whose program is missing
│   ├── ssh.sh               # check_ssh        — from hypr/config/setup/envvars.lua and scripts/ssh/setup.sh
│   ├── calendar.sh          # check_calendar   — from scripts/calendar/calendar-sync.timer and the keyring
│   └── defaults.sh          # check_defaults   — from envvars.lua's hl.env(apps.*) lines, options/, mimeapps.list
└── test/
    ├── run-tests.sh         # Dependency-free harness; auto-discovers test-*.sh
    └── test-*.sh            # One per module, plus lib and entry point; sourced into one shell
```

All modules are sourced into a single shell, so: one public `check_<name>` function each, private helpers prefixed (`_ref_`, `_bin_`, `_svc_`, `_sddm_`, `_upd_`, `_way_`, `_wsm_`, `_hctl_`, `_hw_`, `_as_`, `_ssh_`, `_def_`), and reserved names (`group ok err warn note summary doctor_reset doctor_q doctor_require_repo _finding`) are never redefined. Host probes (`pgrep`, `pacman`, `busctl`, `command -v` via `_way_have_cmd`, `/sys/class/drm` via `_hw_present_outputs`, `$HOME` via `_wsm_home`, the build script's `--check` via `_wsm_current`) each live in their own tiny function so tests can stub them — or aim them at a fixture, which is what `DOCTOR_DRM_SYSFS` does.

`ok` is the all-clear and nothing else — print it only when a check found nothing at all, never as a consolation summary. Every path in a fix hint goes through `doctor_q`, and hints never contain `<placeholder>` text (the shell parses `<foo>` as a redirection).
