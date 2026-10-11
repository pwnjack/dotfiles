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

Wallpaper image -> `wal -i` -> `scripts/theming/apply-wal.sh` fans the palette out to every consumer. `hypr/apply_wal_colors.sh` renders `colors-hyprland.lua` for Hyprland and `colors-hyprland.conf` for Hyprlock; the tracked `colors.lua` and `colors.conf` files are symlinks to those cached outputs. Changing the wallpaper via `scripts/hyprland/wall.sh` triggers this pipeline automatically. Generated state lives under `~/.cache` (`current_wallpaper`, `wal/colors-hyprland.lua`, `wal/colors-hyprland.conf`, `wal/rofi-wallpaper.rasi`, `wal/colors-rofi.rasi`, `wal/colors-waybar.css`, `wal/ghostty-colors`, `wal/thunar-gtk.css`, `wal/cava-config`, `wal/btop.theme`, `wal/starship.toml`, `wal/vesktop.theme.css`, `wal/zen-userChrome.css`, `wal/spicetify-color.ini`, `waypaper-config.ini`); the repo tracks only symlinks to it, so wallpaper switches never dirty git.

Components that need more than a plain include own a `<component>/apply_wal_colors.sh`. `scripts/theming/apply-wal.sh` is the driver: it **globs** for those scripts rather than listing them, so adding a themed component is one new file — no edit to the driver, to `wall.sh`, or to `install.sh`. Both of those call the driver and name no component.

Waybar is never reloaded for a new palette: `reload_style_on_change` restyles it in place when `~/.cache/wal/colors-waybar.css` changes. A full reload rebuilds the bar, which drops its reserved zone and resizes every tiled window for a moment (ncurses apps such as tty-clock see a SIGWINCH). `waybar/style.css` imports that file by relative path, as `swaync/style.css` does, not through a symlink: Waybar 0.15's watcher resolves a symlinked import against its own working directory and silently watches nothing.

`wall.sh` holds a cache-backed `flock` while generating and applying a palette,
reads the current selection after acquiring it, and reports generation or
component failures; success posts no notification, since a toast would land
on the transition. It generates into a staging
cache (`PYWAL_CACHE_DIR=~/.cache/wal/next`, schemes shared by symlink) while
awww's transition plays, and publishes with `wal --theme` 60% of the way
through the transition Waypaper configured (`publish_delay_ns`) (`awww img` returns as it starts; Waypaper saves its
config just after, which dates the newest change). Generating in place would
publish at once, because consumers watch the cache. A wallpaper replaced during
the wait is staged again; a run that queued behind one which already published
the same palette exits quietly. `stat` and `awk` run under `LC_ALL=C`, because a
comma-decimal locale (such as `it_IT`) changes their decimal point. The fan-out driver attempts all
components and returns nonzero on partial failure; `install.sh` handles that
status as a warning.

Every `apply_wal_colors.sh` must:

1. Render into `~/.cache/wal/` and never write a tracked file.
2. **Always leave its output existing**, falling back to defaults when the pywal input is missing. The repo tracks a symlink to that output, and a dangling tracked symlink is an ERROR in `doctor.sh` — on a fresh checkout the cache is empty.
3. Be idempotent, and a no-op when its component is not installed.
4. Reload its own running consumer if that is possible. The driver knows nothing about `swaync-client` or `SIGUSR2`.

`scripts/theming/palette.sh` is the shared loader: `wal_load` fills a `wal` array from `~/.cache/wal/colors` (with a built-in fallback palette), and `wal_readable_on <hex>` returns whichever of the darkest/lightest palette entries stays legible on that background. `wal_oklch <hex> <lmin> <lmax> <cmax> [dl]` is the hex form of the CSS themes' `oklch(from …)` clamp, for consumers that take only hex (Spicetify); it round-trips an unclamped colour, and clamping colour0 gives the same surfaces as the Vesktop and Zen CSS. Use it rather than re-parsing pywal output — a wallpaper palette gives no contrast guarantees, so any fixed text colour is unreadable on some wallpapers.

Four components are templated (`<component>/<name>.in` -> rendered to cache -> a symlink to it, tracked for all but Zen): **cava** and **starship**, because neither program has an include mechanism, and **Vesktop** and **Zen** (below). Edit the `.in` file, never the symlink. cava is templated rather than using its native `theme =` support because cava 0.10.7, the version this was measured on, corrupts the heap on any vertical `gradient`, theme file or not — `horizontal_gradient` is the working path. **btop** uses its native theme directory instead (its script sends `SIGUSR2`, btop 1.4's hot reload, the same as Ctrl+R), and **fastfetch** needs nothing: its `keyColor` values and the distro logo are ANSI indices, which the terminal already resolves to the pywal palette. **bat** is the same (`bat/config` sets `--theme=ansi`; CachyOS makes it the `MANPAGER`). **Ghostty** includes the rendered `ghostty-colors` (`config-file = ?colors`), and its script sends `SIGUSR2` so running instances reload it. wal's live recolour is only OSC 4 overrides, and an OSC 104 reset falls back to the palette Ghostty last loaded. ncurses apps send that reset when they restart the screen (tty-clock does it on every resize), and a Waybar reload resizes windows for a moment. **Neovim** loads pywal's own `colors-wal.vim` through pywal16.nvim (`nvim/lua/plugins/colorscheme.lua`, tokyonight when that file is absent); `nvim/apply_wal_colors.sh` renders nothing and re-applies the scheme in running instances over their `$XDG_RUNTIME_DIR/nvim.<pid>.0` sockets with `--remote-expr`, never sending keys. The plugin does not set `g:colors_name`, so the plugin spec sets it from a `ColorScheme` autocmd; instances whose user picked another scheme are left alone. **Vesktop** renders `vesktop/pywal.theme.css.in` with `wal_render` into a Vencord theme; the tracked `vesktop/themes/pywal.theme.css` symlink is switched on once under Vencord's Settings > Themes, which is Vesktop's own state. It recolours surfaces only (backgrounds, borders, scrollbars, brand fills) and never a text or foreground variable, so every text pairing stays one Discord drew. The base is clamped in OKLCH to lightness 0.21–0.26 with capped chroma: the cap keeps surfaces inside Discord's own dark range, and the floor keeps its layering on a near-black palette. The accent is clamped to Discord's brand lightness, which its white button labels expect. Vesktop watches its themes directory, not the symlink's target, so the script runs `touch -h` on the symlink to recolour open windows live. **Zen** renders `zen/userChrome.css.in` the same way, with the same base clamp and a lighter accent (it marks tabs and focus rings rather than filling buttons under white labels), but its profile lives in `~/.zen`, outside the repo, so nothing tracked links to the output. Instead the script finds the profile Zen launches (the `[Install…]` `Default=` in `profiles.ini`, which can differ from the one marked `Default=1`), links its `chrome/userChrome.css` to the cache, and adds the `toolkit.legacyUserProfileCustomizations.stylesheets` pref to its `user.js`, once. A link to an earlier `zen-userChrome.css` is re-pointed; any other `userChrome.css` is the user's own and is left alone. Private and unsynced windows keep Zen's own look. Zen's gradient generator writes its colours as inline styles, the background on its own `.zen-browser-generic-background` elements rather than the root, so the CSS targets those elements with `!important`; the open address bar likewise paints from `--zen-urlbar-background-base` on `.urlbar-background`, not from `--zen-urlbar-background`, which nothing reads. It also pins the toolbar text to Zen's dark-mode white, because Zen picks that text colour for the gradient being replaced. Zen reads the file only at startup, so a new palette shows from the next launch. `test/test-theming.sh` runs every apply script with a throwaway `HOME` so that this one never touches a real profile. **Spotify** uses a tracked Spicetify theme, `spicetify/Themes/Pywal/`: a deliberately tiny `user.css` on Spotify's stock layout (generated class names are renamed between releases, which is what broke the third-party Tokyo theme's seek animation and volume bar), and a `color.ini` symlink to the scheme `spicetify/apply_wal_colors.sh` computes with `wal_oklch`. Text stays Spotify's white and grey. The script runs `spicetify -n refresh` only while Pywal is the selected theme, on an unpacked client, and never alongside `scripts/spotify/launch.sh`'s patch run: it takes the same lock, and when a patch holds it a detached waiter refreshes once the patch is done. `spicetify/Extensions/pywal-live.js` rereads `colors.css` every 3 s while the window is visible and adopts it as a constructed stylesheet, because Spicetify links `colors.css` from the body and a `<style>` in the head loses to it. `scripts/spotify/spicetify-theme.sh` (run by `install.sh`) selects the theme and extension once in Spicetify's untracked config; loading the extension the first time needs `spicetify apply` and a Spotify restart.

### Wallpaper carousel

`quickshell/wallpaper-carousel/shell.qml` is a separate Quickshell application,
opened on demand by `scripts/hyprland/wallpaper-carousel.sh` (Super+Ctrl+W).
The launcher serialises startup and uses config-specific IPC; it exits on close
to consume no idle RAM. No login autostart is configured.
`carousel-state.sh` reads Waypaper's folder settings, awww's current image and
the shared palette loader on every open. Previews are asynchronous, bounded in
resolution, and virtualised; closing destroys the process after any pending
wallpaper application finishes.
The translucent backdrop uses a Hyprland layer blur rule and follows the shared
blur settings in `decor.lua`; the desktop remains live behind it. Wheel handling
covers the whole overlay.

`carousel-apply.sh` passes the path as an argument to Waypaper with
`--monitor All --no-post-command`, verifies awww and the saved selection, then
runs `wall.sh` synchronously exactly once. Its nonblocking submission lock is
separate from `wall.sh`'s theme lock. Waypaper's own random selection and the
SDDM wallpaper watcher are unaffected by it. Waypaper cannot persist percent signs, and the
query/INI boundary cannot represent line breaks; the helper rejects those names
before submission. See `docs/wallpaper-carousel.md` for checks and measurements.

### Keybindings overlay (Super+H)

`quickshell/keybinds-overlay/shell.qml` is an on-demand, read-only Quickshell
HUD started by `scripts/hyprland/keybinds-overlay.sh` (lock, IPC toggle,
daemonize; exits on close). It reads `scripts/keybinds/keybinds-sheet.sh --json`
on every open. Typing filters in place under a prompt whose line never moves, the
wheel scrolls by pixels only on overflow, and Esc or a click closes it.
`sheet.mjs` is the pure model (filter, highlight, contrast fallback, column
balancing), tested by node; the view is tested offscreen by qmltestrunner. See
`docs/keybinds-overlay.md`.

### Workspace module (cffi/workspaces)

The workspace dots are one native Waybar module, `waybar/workspaces/` (C,
GTK3/cairo, Waybar CFFI ABI 2), drawn on one canvas from one animation clock:
the leaving pill contracts while the arriving dot stretches, both amounts
from the same clock, so the row's width is exactly constant and nothing
beyond them moves by a pixel. The ten CSS-animated custom modules it replaced
could not do that: GTK rounds each animating `min-width` up (a 1 px wobble)
and separate processes landed their updates up to tens of ms apart.
`model.c` (state, parsers), `anim.c` (groups, curves, layout) and `render.c`
are pure and tested headless; `hypr.c` speaks Hyprland's sockets directly and
is tested against fake sockets; it connects and writes each command
synchronously and reads only the reply async, because Hyprland blocks its
main loop from accept() until the request arrives (an async write deadlocked
with Waybar's own synchronous Hyprland calls: a 5 s freeze per window close); `module.c` is the GTK glue and must export all
five `wbcffi_*` functions — Waybar calls `update` and `refresh`
unconditionally. `scripts/waybar/build-workspaces.sh` builds out of tree
(never inside the repo) into `~/.local/lib/waybar/workspaces.so` and renders
`~/.local/state/waybar/workspaces.jsonc` with the absolute `module_path`,
because Waybar `dlopen`s that string verbatim. A content stamp beside the
library (`<lib>.sha256`, a hash of the sources, Makefile and script) decides
whether a rebuild is needed; `--check` compares only and exits 0 current / 1
stale or missing, which is what `doctor.sh` uses. Colours and insets stay in
`style.css` (`#workspaces`, `.active`, `.numbers`); sizes live in `anim.c`.
`scripts/hooks/post-merge` (`post-checkout` is a symlink to it) runs the build
after a pull or branch switch, in the main worktree only, so a pull never
leaves a stale library. `docs/workspaces-native.md` has the build flow and the
way back to the CSS dots: tags `workspaces-css` (before) and
`workspaces-native` (the merge), undone with `git revert -m 1`.

### Update card (Waybar custom/updates)

`quickshell/updates/shell.qml` is the on-demand update card started by
`scripts/hyprland/updates-popover.sh` when the bar's updates module is clicked
(lock, IPC toggle, cursor-anchored, exits on close). Update starts
`scripts/updates/updates-run.sh` under `setsid`: it runs the root helper
`/usr/local/bin/system-update` (installed from `updates/system-update-root.sh`
by `updates/setup-sudo.sh`, one no-argument NOPASSWD rule), then Flatpak, and
`fold.mjs` folds the stream into `$XDG_RUNTIME_DIR/updates/state.json` through
the pure `model.mjs` the card also imports, so card and bar agree. AUR updates
stay in the terminal (`scripts/updates/terminal.sh`). See `docs/updates.md`.

### Capture bar (Super+Shift+S / Super+Shift+R)

`quickshell/capture/shell.qml` is the on-demand screenshot/recording strip
started by `scripts/hyprland/capture-bar.sh` (lock, IPC toggle, exits on close;
`record` while recording stops instead). IPC target `capture`: `ping`,
`toggle <mode>`, `open <mode>`, `close`, `status`, and `run` (a scripted-check
seam: presses the action button, acts only while the strip is open). It writes
only `options/capture-*`, synchronously (`blockWrites`) so the started script
reads what the strip shows. Those files are gitignored per-machine state; a
missing one is the default. The capture starts detached with stdio closed after
Hyprland reports the `capture-bar` layer closed (400 ms fallback); the layer
rules are blur + `no_anim`, so the strip is never in the shot.
`scripts/capture/record.sh` is the only driver of gpu-screen-recorder; it
identifies processes by pid plus `/proc` start time (`since` in
`$XDG_RUNTIME_DIR/capture/recording.json`), serialises stops with a flock, and
drives Waybar `custom/recording` (`interval: once`, signal 11, which it sends on
each change and once a second while recording, so an idle bar runs nothing).
`screenshot.sh` stays the only screenshot command. Both post the shared saved
toast (`scripts/capture/toast.sh`, Open / Show in folder); Show in folder goes
through D-Bus `org.freedesktop.FileManager1`, which several installed file
managers claim, so `scripts/settings/file-manager.sh` (install.sh, and the
panel's File manager row) copies the configured one's service file into
`~/.local/share/dbus-1/services/`. `scripts/hyprland/lock.sh` is
the only lock path (Super+L, power menu, hypridle `lock_cmd`; the one exception is
`scripts/hyprland/startup.sh`, which runs hyprlock directly on autologin, when
nothing records) and locks FIRST:
it starts hyprlock at once and hands `record.sh stop` to a detached process,
because logind's `InhibitDelayMaxSec` is 5 s and a slow save must never delay
the lock; a clip may end with about a second of the lock screen. hypridle sets
`inhibit_sleep = 3` because its auto mode keys on the string "hyprlock" in
`lock_cmd`, which lock.sh's path lacks. The guard fails closed (`flock -w 1`;
only a running same-user hyprlock skips locking). `model.mjs` is the pure
model. See `docs/capture.md`.

### Settings panel (Super+I)

`quickshell/settings-panel/shell.qml` starts on demand through
`scripts/hyprland/settings-panel.sh`, used by both Super+I and Waybar. It exits
on close after pending saves finish; failed saves reopen the panel with an
error. There is no login autostart.
`catalog.json` is the only list of settings and categories. Pages sit in five
sidebar groups and rows in titled sections (`group`, `sections`, `section`);
sliders may declare `ends`/`invert` and rows `dependsOn`. `pages.mjs` is the pure
layer that draws and validates this; `test/catalog.mjs` freezes the row-id set.
Maintenance actions are in the title bar's ⋯ menu. The account card under the
sidebar opens the `about` page (`placement: "footer"`, parsed by `about.mjs`).
Rows may declare
`choices` (valid values enumerated from what is installed, validated on write),
a text `check` (`xkb-*`, `font`, `command`), `optional` and `reload`. Beyond
Hyprland options and `options/` files, the backend drives gsettings plus both
tracked GTK `settings.ini` files, Kvantum, `xdg-mime` into the tracked
`mimeapps.list`, `powerprofilesctl`, hypridle's marked suspend listener and
PipeWire through `pactl` (Sound: devices, ports, card profile, mic level;
volume stays in SwayNC); `docs/settings-panel.md` describes each and its
traps. Rows tagged `live`, and the Displays page, refresh while on screen
only (`pactl subscribe` / `Hyprland.rawEvent`); nothing runs when closed.
Displays edits go through apply-with-revert: a `systemd-run --user` timer
reloads Hyprland after 20 s unless Keep writes the evaluated line to the
untracked `~/.local/state/hypr/monitors.lua`. The frame appears
before values arrive; a short-lived, GTK-free GJS helper reads values outside
the UI thread. One value snapshot covers all categories; switching tabs/search
only builds the selected rows, with no new helper or loading layout shift.
The snapshot refreshes after edits and on every fresh opening.
`scripts/settings/panel-request.sh` serialises requests with a cache-backed
lock. Text fields apply with Return or Apply; sliders save on release.

`quickshell/settings-panel/persist.js` serialises Hyprland apply/save operations into the untracked
`${XDG_STATE_HOME:-~/.local/state}/hypr/overrides.lua`, which `hyprland.lua` loads last (skipped,
with a notification, if it fails to run), so panel use never dirties the repo. It waits for an
`ok` reply before saving, reloads the saved configuration if a write fails,
and propagates failures to the panel's visible status message. Its regression
tests exercise that implementation directly. Resets remove
only the selected override and reload the Lua configuration; there is no
second table of default values. Failed resets attempt to restore the previous
file and reload it. `hyprctl configerrors -j` may report `[""]` when healthy.

`backend.js` preserves custom hypridle/hyprsunset content when editing timeouts
and profiles, and rolls file changes back on reload failure. Night light state
still goes through `nightlight.sh`. Theme colours come from the shared palette
loader at launch. See `docs/settings-panel.md` for measurements and checks.

The Network, Date & Region and Startup pages work as follows. **Network** reads libnm through `nm.js` with the pure
`network.mjs` model; `nmcli monitor` and a 20 s rescan run only while the page is
visible, and `PROTON_MODE = "app"` means the panel shows Proton VPN and opens its app
rather than toggling a profile the app deletes. **Date & Region** writes time zone, NTP,
language and formats through polkit-authorised `timedated`/`localed` calls in `dbus.js`;
`authPending` hides the panel so the polkit dialog is reachable (`authHidesPanel`).
The 12/24 h clock is `options/clock`, rendered by `scripts/waybar/clock-format.sh` into
the `~/.local/state/waybar/clock.jsonc` Waybar include, and hyprlock reads the option.
**Startup** lists `autostart.lua` and manages XDG autostart entries by uwsm's generator
rules; `~/.config/autostart` is per-machine and gitignored, and disabling a system entry
writes a minimal `Hidden=true` override. Panel writes reach `panel-request.sh -` on stdin,
never in argv, so passwords stay out of `ps`.

**Devices** lists wireless peripherals from `scripts/devices/devices.sh`, the one reader shared with Waybar's battery module and the low-battery toast; `shell.qml` runs it on open and every 10 s only while the page is visible, and `alert` is defined once, in the script.

### Spotify (SpotX)

`scripts/spotify/launch.sh` is what starts Spotify: `setup.sh` (run by
`install.sh`, skipped without spotify-launcher) points a per-user copy of
`spotify-launcher.desktop` at it. spotify-launcher swaps in a fresh client
directory on every update, so the marker `.spotx-patched` beside its binary is
gone exactly when the patch is (not in `Apps/`, which Spicetify deletes and
rebuilds whole); without it the wrapper runs `spicetify restore`
(only if the client is unpacked), the latest SpotX-Bash (`-f`, free tier), then
`spicetify backup apply`. The marker means "SpotX applied" and is written before
Spicetify runs: Spicetify's apply drops SpotX's stock `xpui.bak`, after which
SpotX refuses the client, so a Spicetify failure gets its own toast instead of a
retry. SpotX exits 0 on a client newer than it supports; the wrapper compares the
logged versions and warns. Failure starts Spotify unpatched with a toast; the running-Spotify
check happens under the lock, and a running client is never patched. SpotX
`pkill`s `[sS]potify` by name, so the wrapper's file name must not contain it.
See `docs/spotify.md`.

### Night light (hyprsunset)

`hyprsunset` runs as a daemon from `config/setup/autostart.lua` and owns the schedule in `hypr/hyprsunset.conf` — a tracked, panel-writable file, the same arrangement as `hypr/hypridle.conf`. `scripts/hyprland/nightlight.sh` is the **only** thing that talks to `hyprctl hyprsunset`; the keybind ($Mod SHIFT+D toggle, $Mod CTRL+D follow-schedule), the waybar `custom/nightlight` module and the panel's Power rows all call the script.

There is deliberately **no state file** — the daemon is the state, so every surface agrees by construction. A manual override is just a temperature write, which the daemon's own profile timer reclaims at the next scheduled boundary; that is what makes overrides self-expiring with no expiry logic to maintain.

Gotchas, all found by probing the binary rather than reading docs:

- **Profile `gamma` is a multiplier, not a percentage.** `gamma = 100` inside a `profile` block is read as `10000%` and the daemon *exits*. It is optional and defaults to 100%, so the profiles simply omit it. Top-level `max-gamma` **is** a percentage.
- **`identity` has no getter.** Bare `hyprctl hyprsunset identity` is a *setter* returning `ok`, and `temperature` keeps reporting its last set value while identity masks it — so identity state is unreadable. `off` therefore writes the neutral temperature instead of using identity, keeping state readable.
- **`--config` is not a working flag** in v0.4.0 despite the string being in the binary; the path is fixed. Changing the schedule means restarting the daemon (there is no reload request), which is what `quickshell/settings-panel/backend.js` does.
- **A crashed daemon leaves a stale socket**, so `pgrep` is not a liveness probe — only an actual request is.
- `reset temperature` re-applies the active profile; that is the `auto` subcommand.
- The waybar module declares `"signal": 8` so the script can `pkill -RTMIN+8 waybar` for an instant icon update instead of waiting out the interval.
- **Icons need different names in the panel and in notifications** — two separate traps:
  - *In the panel* (GTK4 `icon-name` lookup), symbolic icons work, but **Papirus-Dark ships its symbolic `status/` set with the light theme's `#444444`**, so `night-light-symbolic` renders invisible on a dark plate even though `Gtk.IconTheme.has_icon` returns true. Only entries symlinked into `panel/` are correctly themed. Check the resolved SVG's `ColorScheme-Text` before trusting a symbolic icon.
  - *In notifications*, **swaync 0.12.6 renders nothing at all for Papirus-Dark's symbolic icons** — it reserves the icon slot and leaves it blank. `notify-send -i` must use the **non-symbolic** name (`weather-clear-night`, not `weather-clear-night-symbolic`). A name that renders in the panel is no evidence it renders in a toast; screenshot the toast.

### Virtual surround (PipeWire)

`pipewire/pipewire.conf.d/60-virtual-surround.conf` is the only tracked PipeWire
config: a filter-chain sink, *Virtual Surround 7.1 (headphones)*, that renders 8
channels binaurally through libmysofa's KEMAR HRTF into stereo. It is chosen per
application and is not meant to be the default output; its output follows the
default sink and names no device. See `docs/virtual-surround.md`.

### SDDM greeter wallpaper sync

`sddm/watch_wallpaper.sh` follows awww changes and asks `sddm/update_sddm.sh`
to refresh the greeter background. The passwordless-sudo target is a root-owned
copy installed under `/usr/local/bin`, while the tracked
`sddm/update_sddm_root.sh` remains its source and upgrade path. This separation
prevents the automatic NOPASSWD path from running a user-writable script as
root; the rule installed by setup pins the helper's sole argument to the
invoking username. The manual path remains privileged: `setup-sudo.sh` installs
from `$SCRIPT_DIR/update_sddm_root.sh` in the user's home, so anything able to
change that source gains root execution the next time setup is run. Re-run
setup only after reviewing source changes. The SDDM doctor check uses the
effective `sudo -l` grant, validates the installed helper and resolved theme
directory ownership, and detects stalled propagation. The helper remains
privileged only for its destination: wallpaper discovery and ffmpeg decoding
run as the target user, while root creates a temporary JPEG inside the theme's
`Backgrounds` directory and atomically renames it over the greeter background
after a successful decode. The resolved theme and `Backgrounds` directories
must remain root-owned so an unprivileged user cannot substitute either side
of that privileged rename.

### SSH agent

OpenSSH's packaged `ssh-agent.socket` (socket-activated, keys in memory only)
holds the key, so its passphrase is asked once per login. `SSH_AUTH_SOCK` is set
by `hypr/config/setup/envvars.lua` (`$XDG_RUNTIME_DIR/ssh-agent.socket`, guarded
against an unset runtime dir): Hyprland launches every app and terminal, so the
plain `Hyprland` session and the uwsm one both get it — `environment.d` would
reach only the latter. The line's `true` flag (`hl.env`'s `dbus` argument) also
exports it to the systemd user manager and the D-Bus activation environment each
session, which uwsm's fixed export list would not, so systemd units and
D-Bus-activated apps (Ghostty) see it. Already-open terminals get it at the next
login; `setup.sh`'s `set-environment` only covers the current session until then. The
tracked `ssh/config` holds only `AddKeysToAgent yes`.
`~/.ssh` is outside the repo, so `scripts/ssh/setup.sh` (run by `install.sh`
after the deploy step, no prompt) gives it a pointer: `Include ~/.config/ssh/config`
as the **first** line of `~/.ssh/config`, because a line after a `Host` or
`Match` block applies to that block alone. ssh uses the first value it reads, so
the tracked `AddKeysToAgent yes` takes precedence over one already in the user's
config (setup prints a notice; edit `ssh/config` to keep theirs). It backs the
file up to `<backup dir>/.ssh/config` first, as the deploy step does, and prints
the restore command. It never edits a symlinked `~/.ssh/config`: a symlink whose
target already has the Include is simply accepted, otherwise it is reported. A
symlink problem, an existing backup, or a failed enable skips only that step; the
rest still runs and setup exits 1. ssh refuses an Include target that is group or
world writable, so setup repairs the fragment with `chmod go-w` and doctor's
`check_ssh` warns when it finds it that way. `checks/ssh.sh` reads the unit name
and Include line from `setup.sh` and the socket name from the `envvars.lua` line
(both use the same sed).

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

Four mechanisms, one source each. **`mimeapps.list`** (tracked, written by the
panel's Default Apps page through `xdg-mime`) decides what opens links and files
for `xdg-open`, GIO, portals and file managers. **Environment variables**
`BROWSER`, `TERMINAL`, `EDITOR` and `VISUAL` are exported by
`hypr/config/setup/envvars.lua` from `options/` (via `apptype.lua`), with
`hl.env`'s D-Bus flag so systemd units and D-Bus-activated apps get them; a
panel change reloads Hyprland, so new programs see it at once. Nothing in
`~/.profile` is needed, and a distro default there once left `BROWSER=firefox`
with Firefox gone (gh failed to open its login page). **xdg-terminal-exec**
(package, in `install.sh`) opens desktop entries with `Terminal=true` for GLib
apps and uwsm; `scripts/settings/terminal.sh` (install.sh, and the panel's
Terminal row) writes the untracked `~/.config/xdg-terminals.list` naming the
TerminalEmulator entry whose `Exec` runs `options/terminal`, and leaves a
hand-written list alone. **D-Bus `FileManager1`** is `file-manager.sh`'s (see
Capture bar). `TERM` is never set by config: each terminal sets it.
`check_defaults` warns when a variable in this shell or the systemd manager,
xdg-terminal-exec, or a `mimeapps.list` entry whose desktop file exists names a
program that is not installed; associations for apps this machine never had are
skipped, since lookups fall back past them.

### User preferences (`options/`)

Simple text files (one value per file) that scripts read at runtime: `browser`, `terminal`, `editor`, `codeeditor`, `filemanager`, `font`, `font-gtk`, `launchertype`, `mainmonitor`, `cursortheme`, `aurhelper` (the AUR update command, `paru -Syu` by default), the login switches `autologin` (lock the screen after an autologin), `protonvpn` and `randomwallpaper` (on when the file says `enabled`, off otherwise, empty included), `capture-freeze`, `capture-shot-target`, `capture-rec-target`, `capture-delay`, `capture-annotate`, `capture-audio`, `capture-mic` (the capture strip's, untracked: a missing file is the default), `clock`, and the settings panel's Bar page modes `bar-cpu`, `bar-memory`, `bar-gpu`, `bar-disk`, `bar-network`, `bar-updates` and layout `bar-position`, `bar-style`, `bar-opacity`, `bar-border`, `bar-output` (empty = every monitor), `clock-seconds`, `bar-workspaces` (see `docs/settings-panel.md`). `wallpaper` is a symlink to `~/.cache/current_wallpaper`, maintained by `wall.sh`. Scripts read these directly (`cat` or `read -r`) and use the value as-is. `mainmonitor` and `bar-output` are the value preferences that are legitimately empty: empty means "no preference" (for `bar-output`, every monitor), and every consumer resolves it itself. hyprlock draws on every monitor via `$monitor =` in `hardware/primary.conf`; `wall.sh`, `restore-wallpaper.sh`, and both SDDM scripts fall back to whichever monitor awww reports first. Nothing guesses a connector name: a tracked default such as `DP-1` or `eDP-1` is wrong on the next machine, which `scripts/doctor/checks/hardware.sh` guards. `hypr/config/hardware/monitor.lua` is host-neutral for the same reason (per-machine rules live in the untracked `~/.local/state/hypr/monitors.lua`, written by the settings panel's Displays page and loaded if present) and uses `highres@highrr`, not `preferred` or bare `highrr`: measured on a 2560x1440 144 Hz panel, `preferred` selected 2560x1440@59.951, while applying the combined form from 1024x768@60 selected 2560x1440@143.998.

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

- `hyprland/` — Session and desktop scripts: startup, `lock.sh`, wallpaper switching (`wall.sh`, `restore-wallpaper.sh`), the Quickshell launchers (`settings-panel.sh`, `capture-bar.sh`, `keybinds-overlay.sh`, `updates-popover.sh`, `wallpaper-carousel.sh` and its `carousel-*.sh` helpers), `screenshot.sh`, `colorpicker.sh`, media control, night light (`nightlight.sh`) and the AI sidebar launcher (`launch-chatbox.sh`, Super+A)
  - Media: `medialib.sh` is a sourced helper that picks *which* player the waybar module follows (first `Playing`, else first with a title). `mediaexec.sh` renders it (waybar JSON, or one plain line for hyprlock with `--plain`) and `mediactl.sh` drives transport through the same choice, so the title shown and the player controlled can never diverge. Successful local controls signal Waybar for an immediate refresh; the five-second poll only catches changes made inside a player. There is deliberately no stored player preference — bare `playerctl` picks by bus registration order, and selecting per-poll is what removed the old left-click scope toggle.
- `waybar/` — Bar management (`waybar.sh`, `waybartoggle.sh`), the Bar page renderers (`bar-modes.sh`, `clock-format.sh`), the `network.sh` and `updates.sh` modules, `build-workspaces.sh`, plus `battery.sh`: the battery module for the whole machine. It reads `/sys/class/power_supply` directly because waybar's own module counts only `SCOPE=System` and so reports nothing on a desktop whose only batteries are peripherals. `SCOPE` selects behaviour rather than filtering — `Device` peripherals stay hidden until they fall below 25% (the module appearing is the warning, which is what keeps it stateless), while system batteries are always visible and accumulate, with the alert class taking the minimum across discharging ones. A powered-off peripheral keeps its node *and* its last reading, so `POWER_SUPPLY_ONLINE` present-and-`0` is the skip test; a laptop battery has no `ONLINE` at all and must not be caught by it. Charge state is trusted for system batteries only. `BATTERY_SYSFS` overrides the scan root — that seam is how `test-battery.sh` runs without hardware, and how the bar is screenshotted with the module forced visible without editing a tracked file.
- `devices/` — `devices.sh`, the one reader of wireless peripheral batteries and connection state (USB headsets through the optional `headsetcontrol`); Waybar's battery module, the low-battery toast (`battery-alert.sh`) and the panel's Devices page all consume its JSON
- `capture/` — `record.sh`, the only driver of gpu-screen-recorder, and `toast.sh`, the shared saved toast (see Capture bar); `fakes/` are test stubs
- `updates/` — the update card's planner and runner (`updates-plan.sh`, `updates-run.sh`), `terminal.sh` for the terminal paths, and the Node modules `fold.mjs` and `tooltip.mjs` (see Update card)
- `settings/` — the panel's request runner (`panel-request.sh`), default file manager and terminal wiring (`file-manager.sh`, `terminal.sh`), and `update.sh`, the terminal update (AUR helper from `options/aurhelper`, then Flatpak)
- `theming/` — Pywal fan-out driver (`apply-wal.sh`) and the shared palette loader (`palette.sh`)
- `fonts/` — `apply-font.sh`, which writes `options/font` and `options/font-gtk` into every config that names a font
- `spotify/` — the SpotX launch wrapper, its desktop-entry setup and the Spicetify theme selection (see Spotify)
- `ssh/` — `setup.sh`, the `~/.ssh/config` Include (see SSH agent)
- `agents/` — `setup.sh`, which wires in the AI agent harness
- `keybinds/` — `keybinds-sheet.sh`, the one parser of `keybinds.lua`; `docs/` — `generate-keybindings.sh`, which renders `docs/keybindings.md` from it
- `doctor/` — the library and check modules behind `doctor.sh` (see Doctor architecture)
- `hooks/` — the git hooks (`pre-commit`, `post-merge`, with `post-checkout` a symlink to it) and `snapshot.sh`
- `lib/` — sourced helpers: `assert.sh` (test assertions), `deploy.sh` (the installer's copy and backup plan), `hypr-vars.sh`, and `wallpaper.sh` (which image is the current wallpaper)

Scripts are bash, apart from the two Node modules in `updates/` and one Python test stub in `capture/fakes/`. They check for command existence before running and read preferences from `options/`.

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
│   └── defaults.sh          # check_defaults   — from envvars.lua's hl.env(apps.*) lines, options/, mimeapps.list
└── test/
    ├── run-tests.sh         # Dependency-free harness; auto-discovers test-*.sh
    └── test-*.sh            # One per module, plus lib and entry point; sourced into one shell
```

All modules are sourced into a single shell, so: one public `check_<name>` function each, private helpers prefixed (`_ref_`, `_bin_`, `_svc_`, `_sddm_`, `_upd_`, `_way_`, `_wsm_`, `_hctl_`, `_hw_`, `_as_`, `_ssh_`, `_def_`), and reserved names (`group ok err warn note summary doctor_reset doctor_q doctor_require_repo _finding`) are never redefined. Host probes (`pgrep`, `pacman`, `busctl`, `command -v` via `_way_have_cmd`, `/sys/class/drm` via `_hw_present_outputs`, `$HOME` via `_wsm_home`, the build script's `--check` via `_wsm_current`) each live in their own tiny function so tests can stub them — or aim them at a fixture, which is what `DOCTOR_DRM_SYSFS` does.

`ok` is the all-clear and nothing else — print it only when a check found nothing at all, never as a consolation summary. Every path in a fix hint goes through `doctor_q`, and hints never contain `<placeholder>` text (the shell parses `<foo>` as a redirection).
