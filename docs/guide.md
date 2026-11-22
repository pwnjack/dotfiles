# Guide

Everything beyond the [README](../README.md): how the pieces fit, day-to-day use,
customisation and maintenance. Keybindings have their own generated page,
[keybindings.md](keybindings.md).

Deep dives, one per component:

- [Settings panel](settings-panel.md) (`Super + I`)
- [Capture bar](capture.md): screenshots and screen recording (`Super + Shift + S`)
- [Calendar](calendar.md): iCloud events on the bar and in a card (`Super + Shift + E`)
- [Wallpaper carousel](wallpaper-carousel.md) (`Super + Ctrl + W`)
- [Keybindings overlay](keybinds-overlay.md) (`Super + H`)
- [Update card](updates.md): the bar's updates module
- [Native workspace module](workspaces-native.md): the bar's workspace dots
- [Spotify](spotify.md): SpotX ad-blocking and the wallpaper theme
- [Virtual surround](virtual-surround.md): 7.1 for headphones
- [SDDM greeter sync](../sddm/README.md): the login screen follows the wallpaper
- [WoW / Battle.net](gaming-wow.md): gaming setup notes

The design notes and traps behind each piece (theming, the machine-state
overlay, options, the doctor, the desktop clock, night light, default
applications and more) are in [internals/](internals/). The bar's cards that
have no page above are described there too: the
[weather card](internals/weather-card.md), the
[media card](internals/media-card.md) and the
[sound popover](internals/sound-popover.md).

## Core stack

| Component | Application |
|-----------|-------------|
| Window manager | Hyprland |
| Status bar | Waybar |
| Launcher | Rofi |
| Settings panel and overlays | Quickshell (started on demand, exit when closed) |
| Terminal | Ghostty (`options/terminal`) |
| Notifications | SwayNC |
| Lock screen | Hyprlock |
| File manager | Strata / Yazi (`options/filemanager`) |
| Browser | Zen Browser (`options/browser`) |
| Editor | Neovim (LazyVim) |
| Shell | Fish + Starship |
| Colours | matugen, derived from the wallpaper |
| Desktop clock | eww (`options/desktop-clock`) |

Strata is the default file manager. `Super + E` and “Show in folder” follow
`options/filemanager`.

## Structure

`CLAUDE.md` carries the detailed `hypr/config/` breakdown and the rules that
hold on every edit; [internals/](internals/) has the design notes behind each
piece. Files ending in `.in` are templates rendered into
`~/.cache/wal/`; what reads the result is a symlink to it — edit the template.

## Everyday use

### Keybindings

The README's five keys are the ones worth memorising, along with `Super + Q`
or `Super + W` to close a window and `Super + L` to lock.
**[docs/keybindings.md](keybindings.md) has every binding**, grouped by
section — or press `Super + H` for the same list, searchable, without leaving
the desktop.

Navigation follows one rule: **every window and workspace binding carries `Super`**,
so `Alt`/`Ctrl` + arrows always reach the focused app (browser back/forward,
shell word jumps, editor line moves, TUI prompts). On the arrows, `Super` alone
moves focus, `+ Shift` moves the window, `+ Alt` resizes it, and `+ Ctrl`
switches workspace (`+ Ctrl + Shift` takes the window along). Ghostty's own
`Ctrl + Enter` fullscreen is unbound; `Super + F` is the one fullscreen key.

### Feature notes

The **colour picker** (`Super + Shift + C`) copies the selected screen pixel as
a lowercase hex value and sends a notification.

**Annotation** is opt-in, so the quick grab stays quick: `Super + S` saves a
region, `Super + Alt + S` captures one straight into swappy, and the capture strip
(`Super + Shift + S`) has an Annotate toggle for the same flow. Annotated images
land in `~/Pictures/Screenshots` with an `_annotated` suffix. swappy reports
success by closing, which means you can save *or* copy one annotation, not both.

The **weather** beside the clock shows the condition and temperature now; its
tooltip adds wind, humidity, pressure and the sun times. Left-click opens the
weather card: the next 21 hours in 3-hour steps and seven days, each with its
low and high on one scale. The card opens on the last forecast and asks
Open-Meteo for a new one only when that is older than 15 minutes. The place
is the one the bar's `waybar-weather` service found; to set it by hand, put
`<city>,<country>` in `~/.config/waybar-weather/cityname`. See
[weather-card.md](internals/weather-card.md).

The **media module** shows the artist and title of what is playing, dimmed
while it is paused, and hides when no player is open. Left-click opens the
media card: album art, a seek bar and previous, play or pause, and next. With
two players open (music and a browser tab, say) a row of chips switches which
one the card controls; the bar goes on choosing its own. Middle-click plays or
pauses and the scroll wheel skips tracks. In the card, `Space` plays or
pauses, the left and right arrows seek five seconds and `Esc` closes. See
[media-card.md](internals/media-card.md).

The **volume icon** opens the sound popover: output and input devices, per-app
volume and which output each app plays on. Device names and hidden devices are
set on the settings panel's Sound page; see
[sound-popover.md](internals/sound-popover.md).

The **pending-updates module** sits right after the CPU, memory, GPU and disk
readouts and appears only when repository, AUR or Flatpak updates exist — the
module showing up is the notification. Left-click opens the update card, which
lists what is pending and runs the repository and Flatpak update with a
progress bar; AUR updates stay in the terminal. Right-click forces a refresh.
The AUR command comes from `options/aurhelper`, and repository checks need
`pacman-contrib` (`checkupdates`). See [updates.md](updates.md).

The **night-light module** reflects the temperature `hyprsunset` has actually
applied. Left-click (or `Super + Shift + D`) switches between warm and neutral
as a manual override — both are overrides, and the daemon reclaims either at
the next scheduled boundary. Right-click (or `Super + Ctrl + D`) hands control
back to the schedule in `hypr/hyprsunset.conf` (rendered from
`defaults/hypr/hyprsunset.conf`) immediately.

The **calendar** shows your iCloud events: the bar's clock opens the month,
the next-event pill the coming days, and `Super + Shift + E` a new-event
sheet. Sign in on the settings panel's Calendar page; see
[calendar.md](calendar.md).

The **desktop clock** is an eww widget at the bottom right of the wallpaper,
on by default when eww is installed. Switch it off, or change its font, on the
Appearance page (`options/desktop-clock`, `options/desktop-clock-font`); it
follows the 12 or 24 hour choice and the main display.

The **idle lock** engages after 30 minutes without input and the displays turn
off after an hour (the Power page changes both). For five seconds after an idle
lock, a key press or a mouse move dismisses it without a password; `Super + L`,
the power menu and suspend ask at once.

The **AI sidebar** (`Super + A`) opens aichat in a narrow Ghostty window on its
own special workspace; its API key comes from `~/.config/.env` (see below).

`Super + Shift + B` reloads Waybar (and starts it if it is not running);
`Super + Alt + B` shows and hides it.

### Idle efficiency

The settings panel, wallpaper carousel, keybindings overlay, capture bar,
calendar card, media card, sound popover, update card and weather card are launched on
demand and exit when closed, so none keeps a UI runtime resident. The desktop
clock's eww daemon runs only while the clock is on, and the time costs no
process per tick. The workspace dots are a native
Waybar module that listens to Hyprland's event socket instead of polling.
Media, night-light, recording, next-event and update modules refresh on a
Waybar signal when something changes; their intervals are safety fallbacks
rather than the primary refresh path. The GPU module makes one `nvidia-smi`
call per five-second poll, and none while the settings panel's Bar page hides
it.

### Media

Media keys play/pause and skip in the player the bar shows; `playerctl` does
the same from a terminal. The bar's media module opens the media card (see
[Feature notes](#feature-notes)).

### Clipboard

`Super + C` opens the clipboard history in Rofi. The same from a terminal:

```bash
cliphist list | rofi -dmenu | cliphist decode | wl-copy
```

## Configuration

### Configuration files

| Component | Location |
|-----------|----------|
| Hyprland | `~/.config/hypr/hyprland.lua` |
| Waybar | `~/.config/waybar/config.jsonc` |
| Terminal | `~/.config/ghostty/config` |
| Shell | `~/.config/fish/config.fish` |
| Fuzzy finder (Ctrl+R history, Ctrl+T file, Alt+C cd) | `~/.config/fish/conf.d/fzf.fish` |
| Git diffs (delta; identity stays in `~/.gitconfig`) | `~/.config/git/config` |
| Editor | `~/.config/nvim/` |
| Keybinds | `~/.config/hypr/config/software/keybinds.lua` |

### Quick edits

```bash
# Change default browser
echo "firefox" > ~/.config/options/browser

# Change default terminal
echo "ghostty" > ~/.config/options/terminal

# Change primary monitor. Leave this EMPTY for no preference: hyprlock then
# draws on every monitor, and wallpaper scripts use the first monitor awww
# reports (what a single-monitor machine wants). The settings panel (Super + I)
# writes this file, and the overlay renders the lock screen's monitor from it.
echo "HDMI-A-1" > ~/.config/options/mainmonitor

# Edit keybindings
nvim ~/.config/hypr/config/software/keybinds.lua
```

### Default applications

The settings panel's **Default Apps** page (`Super + I`) sets the apps the
keybindings launch and what opens each kind of link and file. How each choice
reaches programs is in [default-apps.md](internals/default-apps.md).

### User preferences

Simple text files in `~/.config/options/`, mostly written by the settings
panel. A change you make by hand or in the panel is kept as a per-machine
override, and deleting a file resets it to the default.
[options.md](internals/options.md) describes the files, and
[state.md](internals/state.md) how the overlay renders them.

### Wallpaper carousel

`Super + Ctrl + W` toggles a fullscreen wallpaper carousel on the focused
monitor. Browse with Left/Right, the mouse wheel, or a card click. Press Enter,
click the selected card, or use **Apply wallpaper** to apply to all monitors.
`Ctrl + F` searches filenames; `Escape` closes without applying a selection.

The carousel reads the folder from Waypaper and keeps the existing awww/matugen
theme pipeline. `Super + Shift + W` still selects a random wallpaper; run
`waypaper` for the original picker and folder settings. Quickshell starts on
first use. See [controls, integration, and verification](wallpaper-carousel.md).

### Wallpaper colours

matugen draws a dark Material palette from the wallpaper. The settings panel's
Appearance page (Palette section) picks its scheme, contrast and source colour
(`options/theme-scheme`, `options/theme-contrast`, `options/theme-prefer`) and
regenerates the current wallpaper's palette when you change one.

Colours apply to Hyprland, Hyprlock, Waybar, Rofi (text and borders), SwayNC,
Ghostty, Strata, cava, btop, Neovim, the Starship prompt, the desktop clock,
Vesktop (Discord), Zen Browser and Spotify (through Spicetify; see
[spotify.md](spotify.md)); fastfetch and bat follow the terminal palette.
[theming.md](internals/theming.md) has the pipeline, each component and how to
add one; to re-render by hand, see Troubleshooting.

### Visual tweaks

**Blur and rounding:** `~/.config/hypr/config/looks/decor.lua`

```lua
hl.config({
    decoration = {
        rounding = 18,
        blur = { enabled = true, size = 4, passes = 2 },
    },
})
```

**Animations:** `~/.config/hypr/config/looks/animations.lua`

Most of these values also have a row on the settings panel's Appearance,
Windows and Animations pages, which writes per-machine overrides instead of
editing the tracked files.

### Displays

Use the Displays page of the settings panel (`Super + I`). Per-machine rules
are written to `~/.local/state/hypr/monitors.lua`, which
`hypr/config/hardware/monitor.lua` loads; the tracked file itself stays
host-neutral.

### Startup applications

Edit `~/.config/hypr/config/setup/autostart.lua` and add a line to its
`hyprland.start` handler:

```lua
hl.exec_cmd("your-app")
```

A daemon that should come back after a crash goes through
`scripts/hyprland/respawn.sh`, as Waybar, SwayNC, hypridle and hyprsunset do:

```lua
hl.exec_cmd("$HOME/.config/scripts/hyprland/respawn.sh your-daemon")
```

It restarts the daemon when it dies uncleanly, leaves it down after a clean
exit or `pkill`, and stops trying, with a notification, after five crashes in
30 seconds. The packaged systemd user units are not used: when a unit's main
process crashes, systemd kills everything left in its cgroup, which would take
down every window opened from the bar, or a running hyprlock with hypridle.
If the daemon's package also ships D-Bus activation for its unit, as SwayNC's
does, add a drop-in under `systemd/user/<unit>.d/` so the unit skips itself
while your copy runs (see `systemd/user/swaync.service.d/respawn.conf`).

XDG autostart entries are managed on the settings panel's Startup page.

### Waybar modules

Edit `~/.config/waybar/config.jsonc`; `Super + Shift + B` reloads the bar.
Which resource modules show, and the bar's position and style, are set on the
settings panel's Bar page.

### Window rules

Edit `~/.config/hypr/config/software/rules.lua`:

```lua
hl.window_rule({
    name = "float-your-app",
    match = { class = "^(your-app)$" },
    float = true,
})
```

## API keys and environment variables

API keys and secrets are stored in `~/.config/.env` (git-ignored).

### Setup

`install.sh` creates `.env` from the template if it is missing. To do it by
hand:

```bash
cp ~/.config/.env.example ~/.config/.env
nano ~/.config/.env    # fill in your keys
```

### Supported keys

- `GEMINI_API_KEY` - Google Gemini (aichat's default model)
- `OPENAI_API_KEY` - OpenAI/ChatGPT (optional)
- `ANTHROPIC_API_KEY` - Claude (optional)
- `GROQ_API_KEY` - Groq (optional)
- `MISTRAL_API_KEY` - Mistral (optional)

The `.env` file is loaded by:

- Fish, on startup
- the AI sidebar launcher (`scripts/hyprland/launch-chatbox.sh`, `Super + A`)

### Security

- `.env` is git-ignored and never committed
- `.env.example` is the tracked template; it holds no real keys
- Keep your API keys private

## AI agent harness (optional)

The Claude Code and Codex harness (global instructions, skills, curated
settings) lives in its own repository,
[agent-harness](https://github.com/pwnjack/agent-harness), so it also works on
machines without these dotfiles. `install.sh` offers it (default No) when
Claude Code or Codex is installed and the harness is cloned:

```bash
git clone https://github.com/pwnjack/agent-harness.git ~/Developer/agent-harness
~/Developer/agent-harness/setup.sh            # or --dry-run to preview
```

Its own documentation covers what it installs and how to remove it.

## Maintenance

```bash
./doctor.sh          # validate the live system
./doctor.sh --help   # usage
```

`doctor.sh` reports and never modifies anything. Every check derives its
targets from tracked files — git's symlink modes, Lua `require()` calls,
`hl.exec_cmd()` targets in keybinds and autostart, and the package arrays in
`install.sh` — so adding a keybind or an autostart entry extends coverage
automatically. There is no list to keep in sync.

| Severity | Meaning | Exit code |
|----------|---------|-----------|
| `ERROR` | The session is broken or will break on next login | exits 1 |
| `WARN` | Degraded — a keybind does nothing, a daemon did not start | exits 0 |
| `INFO` | Tidiness — orphaned config, package drift | exits 0 |

[doctor.md](internals/doctor.md) lists what each check module covers.

The pre-commit hook (`scripts/hooks/pre-commit`, activated by `install.sh` via
`core.hooksPath`) runs `shellcheck` and the suites covering the staged files;
bypass it with `git commit --no-verify`. `./test.sh` runs every suite and
`./test.sh --list` prints them. The Quickshell suites need Qt's
`qmltestrunner`, the model suites Node.js (built-in TypeScript support and
module hooks) and the install, hook and theming fixtures Python 3; a missing
one prints `skip:`, which `TEST_STRICT=1` fails. How suites are discovered and
how the hook builds its snapshot are in
[conventions.md](internals/conventions.md).

GitHub Actions runs the same checks on every push to `main` and every pull
request (`.github/workflows/tests.yml`): `shellcheck -S warning` on every
shell script, then `TEST_STRICT=1 ./test.sh` in an Arch Linux container, from
a copy of the repo at `~/.config` and as an unprivileged user. The doctor stays local, since
it inspects the running desktop.

## Installation details

The install script checks/installs all dependencies, deploys the configs to
`~/.config`, renders this machine's settings from `defaults/`, generates the
matugen palette, and wires up all symlinks.
Deployment copies only tracked files and backs up exactly the existing files it will replace,
including symlinks. Untracked application data stays out of deployment;
directory symlinks and file/directory conflicts are rejected before copying:

```bash
# Clone anywhere (a fresh ~/.config is never empty, so use a staging dir)
git clone https://github.com/pwnjack/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh            # interactive; use --dry-run to preview
```

Log out and select Hyprland from your display manager.

To keep `~/.config` itself under git afterwards (this repo is designed to
live there):

```bash
cd ~/.config
git init -b main
git remote add origin https://github.com/pwnjack/dotfiles.git
git fetch origin
git reset origin/main   # marks repo files as tracked without touching them
```

### Manual

```bash
# The package list is the PACKAGES and AUR_PACKAGES arrays at the top of
# install.sh: install them with pacman and your AUR helper, or let install.sh
# do it (it sends any name your repos lack to the AUR helper).

# Render this machine's settings (options/, GTK and Qt settings, mimeapps.list,
# swaync, hyprsunset and btop config) from defaults/
~/.config/scripts/state/overlay.sh sync

# Generate the palette and render every component's cache file
~/.config/scripts/theming/generate-palette.sh ~/.config/wallpapers/wall1.jpg
~/.config/scripts/theming/apply-wal.sh

# Wire the configured file manager and portal file chooser
~/.config/scripts/settings/file-manager.sh
~/.config/scripts/settings/file-chooser.sh

# Open Terminal=true apps (nvim, yazi, btop) in options/terminal
~/.config/scripts/settings/terminal.sh

# Render Waybar's generated includes and build the workspace module
~/.config/scripts/waybar/clock-format.sh --no-reload
~/.config/scripts/waybar/bar-modes.sh --no-reload
~/.config/scripts/waybar/build-workspaces.sh

# Calendar sync timer, the patching Spotify launcher and its palette theme
# (optional; each skips what is not installed or set up)
~/.config/scripts/calendar/setup.sh
~/.config/scripts/spotify/setup.sh
~/.config/scripts/spotify/spicetify-theme.sh

# SSH agent: the agent socket and the Include in ~/.ssh/config (backed up first)
~/.config/scripts/ssh/setup.sh

# Set fish as default shell (optional)
chsh -s $(which fish)
```

### Keeping your changes in git

```bash
cd ~/.config
git add -A && git commit -m "Describe your change"
git pull   # pick up updates; the post-merge hook re-renders your settings
```

### Backup and restore

```bash
# Backup current config
cp -a ~/.config/hypr ~/hypr-backup-$(date +%Y%m%d)

# Restore
cp -a --remove-destination ~/hypr-backup-DATE/. ~/.config/hypr/
```

Installer backups mirror the relative paths of files it replaces. To restore
one, copy its **contents** back into `~/.config`:

```bash
cp -a --remove-destination ~/.config-backup-YYYYMMDD-HHMMSS/. ~/.config/
```

This restores backed-up files; it does not remove files first introduced by
installation. Existing destination directories should be real directories,
not symlinks to another configuration tree.

## Troubleshooting

**Colours not updating after `generate-palette.sh`:** the generator writes
the palette inputs; components update when the palette is fanned out.
Changing the wallpaper with the carousel or `Super + Shift + W` does this for
you; after generating a palette manually, run:

```bash
~/.config/scripts/theming/apply-wal.sh
```

**Colours look wrong everywhere:** rebuild the palette from the current
wallpaper and apply it everywhere:

```bash
~/.config/scripts/hyprland/wall.sh
```

Running Ghostty and btop windows reload the new palette by themselves.

**Palette symlink broken:** `./doctor.sh` names the missing palette or component
output. A missing Hyprland palette (`~/.cache/wal/colors-hyprland.conf` or
`.lua`) is an ERROR; a missing `~/.cache/wal/colors` or `roles` is a WARN,
because components fall back to the built-in palette. Change the wallpaper
(`Super + Ctrl + W`), or run `generate-palette.sh` on any wallpaper and then
`apply-wal.sh` as above.

**Waybar issues:** press `Super + Shift + B`, which reloads the bar and starts
it if it is not running.

**Screen does not lock when idle**, or **notifications stopped**: the session
daemons are supervised by `respawn.sh`, so restart them through it rather than
by hand (a hand-started copy is unsupervised). Stop the old copy first, since
the wrapper bows out while one is running, and detach the wrapper so closing
the terminal does not end it:

```bash
pkill -x hypridle; setsid -f ~/.config/scripts/hyprland/respawn.sh hypridle
pkill -x swaync;   setsid -f ~/.config/scripts/hyprland/respawn.sh swaync
```

**Logs:**

```bash
# Hyprland log
cat "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log"

# User services (ssh-agent, PipeWire, …) this boot
journalctl --user -b
```

More help: the [Hyprland wiki](https://wiki.hyprland.org).
