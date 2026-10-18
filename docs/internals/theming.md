# Colour flow (matugen) and per-component theming

matugen derives a dark Material palette from the wallpaper. The cache stays
under `~/.cache/wal/`, and component scripts render the same output filenames
as before. The repo tracks symlinks to generated files, so a wallpaper change
never dirties git. Existing theme names, CSS variables such as `--pywal-*`,
and the Neovim plugin name are retained for compatibility.

`~/.cache/wal/` contains `colors`, `roles`, `next/` (staging), `generation.log`, `wallpaper.lock`, `rofi-wallpaper.rasi`, `colors-hyprland.{conf,lua}`, `colors-rofi.rasi`, `colors-waybar.css`, `ghostty-colors`, `strata-theme.toml`, `cava-config`, `btop.theme`, `starship.toml`, `vesktop.theme.css`, `zen-userChrome.css`, `spicetify-color.ini`, `eww-colors.scss`, `colors-wal.vim` and `.eww-reload-failed`.

## Generation and publication

The pipeline is wallpaper image → `scripts/theming/generate-palette.sh` →
`wal/colors` and `wal/roles` → `scripts/theming/apply-wal.sh` → component
outputs and reloads. `scripts/hyprland/wall.sh` runs it automatically after
Waypaper or the wallpaper carousel changes the image. `install.sh` installs
matugen and calls the same generator for the initial wallpaper.

To generate from an image manually, then update the components:

```bash
~/.config/scripts/theming/generate-palette.sh /path/to/wallpaper.jpg
~/.config/scripts/theming/apply-wal.sh
```

The generator accepts an optional output directory after the image. It runs
matugen from a scratch directory with `--dry-run --json hex -q`, using
`matugen/config.toml`, dark mode, the chosen options and the fallback seed
`#6097a1` for flat or near-grey images. The config's `[templates]` table stays
empty: matugen emits JSON; `scripts/theming/matugen-to-wal.sh` validates and
converts it into sixteen plain hex lines in `colors` and `name=#rrggbb` lines
in `roles`. If the chosen scheme or contrast differs from tonal spot at
contrast 0, a second pass uses `-t scheme-tonal-spot --contrast 0` with the
same image, source-colour preference, fallback seed and timeout. Only ANSI
slots 1–6 and 9–14 come from that pass; slots 0, 7, 8 and 15 and all roles
come from the chosen scheme. Defaults need just one pass. Generated hex
colours are lowercase. Missing matugen, failure of either pass or invalid
conversion returns 1 with a diagnostic and leaves the previous palette in
place. Each matugen pass has its own 30-second timeout, overridable with
`GENERATE_TIMEOUT` for tests. Publication to the default cache takes
`flock -w 30` on `wallpaper.lock` and renames `roles` before `colors`, restoring
the previous roles if the second rename fails. Other output directories do
not take this lock, so `wall.sh` can generate into staging while holding it.

`wall.sh` holds a cache-backed `flock` across generation, publication and
fan-out. It reads the current selection after taking the lock, so a queued
request cannot restore an older wallpaper's palette. It generates into
`~/.cache/wal/next` while awww's transition plays, then waits until
`publish_delay_ns`: 60% of Waypaper's transition duration (the duration is
capped at ten seconds). Instant and step-driven transitions do not wait. `awww img` returns
as the transition begins; Waypaper saves its config just afterwards, dating
the newest selection. `stat` and `awk` run under `LC_ALL=C` to keep decimal
points stable in comma-decimal locales.

If the selected wallpaper changes during the wait, it is staged again; after
four rounds the newest queried selection is published without another wait.
A queued run exits quietly if the preceding run already published that image
and the staged slots and roles match. Publication copies complete files into
a temporary directory on the same filesystem, then renames `roles` before
`colors`, restoring the previous roles if the second rename fails. The lock
keeps wallpaper runs serialised; component outputs update
only when the driver subsequently renders them. Generation failure publishes
nothing and sends a failure toast. The driver attempts every component and
returns nonzero on partial failure; `wall.sh` names failed components in its
toast, and `install.sh` reports a warning. Success posts no notification.

`wall.sh` also maintains `~/.cache/current_wallpaper` and the launcher image
include `wal/rofi-wallpaper.rasi`. Palette generation alone does not change
the displayed wallpaper or that symlink.

## Slots and roles

`matugen/config.toml` defines red, green, yellow, blue, magenta and cyan as
custom colours blended towards the wallpaper's source colour. They always
use tonal spot at standard contrast. Gallery measurements with
`scripts/theming/score-palettes.py` and a single pass found that expressive,
fruit salad, neutral and monochrome schemes, and contrast 0.5 and 1, lost
red/green hue identity, chroma or readability. Keeping
the terminal colours independent lets desktop surfaces and accents follow
the selected scheme without changing the meaning of ANSI colours. The slot
mapping is fixed; bright ANSI entries use the text colours of the custom
containers, which remain readable on `surface`.

| Slot | Meaning |
|------|---------|
| 0 | `surface` |
| 1–6 | `red`, `green`, `yellow`, `blue`, `magenta`, `cyan` |
| 7 | `on_surface` |
| 8 | `outline` |
| 9–14 | `on_red_container`, `on_green_container`, `on_yellow_container`, `on_blue_container`, `on_magenta_container`, `on_cyan_container` |
| 15 | `on_surface` |

Hyprland's active border uses `on_surface` (slot 7). Text accents use
`primary` with `on_primary` on primary fills. Selections use container roles
with their matching text roles; decorative ramps use primary tones.

The fixed roles in `wal/roles` are:

```text
surface surface_container_low surface_container surface_container_high
surface_container_highest on_surface on_surface_variant outline outline_variant
primary on_primary primary_container on_primary_container secondary_container
on_secondary_container tertiary_container on_tertiary_container error on_error
primary_t30 primary_t40 primary_t50 primary_t60 primary_t70 primary_t80
primary_t90 primary_t95
```

The primary tones come from matugen's `.palettes.primary`. Templates refer to
roles with `@role_<name>@`, for example `@role_primary@`. Existing `@colorN@`
and `@oncolorN@` tokens still select a slot and text readable on that slot.

`scripts/theming/palette.sh` is the shared loader. `wal_load` fills the
caller's `wal` array from `wal/colors`; `role_load` fills a declared
associative `role` array from `wal/roles`; `wal_role <name>` returns a loaded
role. Slots and roles fall back independently, so an old pywal cache without
`roles` remains usable until the first generation. `wal_render` replaces slot,
readable-text and role tokens after their loaders have run. Use these helpers
instead of parsing matugen JSON in a component.

`wal_readable_on <hex>` chooses the darkest or lightest palette text for a
background using perceived brightness. `wal_oklch <hex> <lmin> <lmax> <cmax>
[dl]` clamps OKLCH lightness and chroma, then applies a lightness offset; it is
the hex equivalent of the CSS themes' `oklch(from …)` clamps for consumers
such as Spicetify that take only hex.

## Generator options and readability

The generator reads three files in `options/`, with tracked defaults in
`defaults/options/`. They can be set from Appearance → Palette in the
settings panel or edited as plain text. Panel changes regenerate the current
wallpaper's palette and recolour the desktop; the panel reads its new colours
on the next opening. The panel offers contrast `-0.5`, `0`, `0.5` and `1`, and
not the `closest-to-fallback` source preference; the generator accepts them
from a hand-edited file:

| File | Default | Controls |
|------|---------|----------|
| `theme-scheme` | `scheme-tonal-spot` | Material scheme: `scheme-content`, `scheme-expressive`, `scheme-fidelity`, `scheme-fruit-salad`, `scheme-monochrome`, `scheme-neutral`, `scheme-rainbow`, `scheme-tonal-spot` or `scheme-vibrant` |
| `theme-contrast` | `0` | Contrast level from `-1` to `1` |
| `theme-prefer` | `saturation` | Source-colour preference: `darkness`, `lightness`, `saturation`, `less-saturation`, `value` or `closest-to-fallback` |

Surrounding whitespace and CR are trimmed. Missing files use the default
quietly; invalid values warn and use the default. See `state.md` for the
machine-state overlay that renders these files.

`scripts/theming/score-palettes.py <directory>` generates and checks every
JPEG, PNG and WebP image directly in the directory. It uses temporary user
state and cache directories, prints each failing image and a final tally,
and exits nonzero on generation or readability failure. For the wallpaper
gallery:

```bash
python3 scripts/theming/score-palettes.py ~/Pictures/Wallpapers
```

The gate requires body text (slot 7) ≥ 7:1, muted text (slot 8) ≥ 3:1,
`primary` ≥ 4.5:1 and each ANSI slot 1–6 ≥ 3:1 against `surface`. Red must
have OKLCH hue in [350°, 50°], green in [110°, 170°], and both must have
chroma ≥ 0.06. Thresholds stay fixed.

## Component contract

Components needing more than a plain include own a
`<component>/apply_wal_colors.sh`. The driver **globs** for these scripts, so
adding one requires no list change in the driver, `wall.sh` or `install.sh`.
Every script must:

1. Render into `~/.cache/wal/` and never write a tracked file.
2. **Always leave its output existing**, using the shared fallback when palette
   input is missing. Missing `colors` or `roles` is a doctor WARN because the
   loaders fall back; missing `colors-hyprland.conf` or `colors-hyprland.lua`
   leaves a dangling tracked symlink and remains an ERROR. Change the wallpaper
   (Super+Ctrl+W), or run the generator with an image and then `apply-wal.sh`.
3. Be idempotent and do nothing to an absent consumer.
4. Reload its own running consumer where possible. Background children must
   not hold stderr open: `wall.sh` reads driver diagnostics to the end, so an
   inherited stderr would stall wallpaper changes.

Tests use temporary `HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME` and runtime
paths and stub session commands. Never run the wallpaper pipeline, overlay
or apply scripts from a worktree against the running desktop's user state.

## Component outputs and reloads

`hypr/apply_wal_colors.sh` renders `colors-hyprland.lua` for Hyprland and
`colors-hyprland.conf` for Hyprlock; tracked `colors.lua` and `colors.conf`
link to those outputs. Waybar watches `wal/colors-waybar.css` with
`reload_style_on_change`, so a new palette never reloads the bar. A full
reload drops its reserved zone briefly and resizes tiled windows. Waybar and
SwayNC import the cached stylesheet by relative path: Waybar 0.15 resolves a
symlinked import against its own working directory and silently watches
nothing. Shared GTK definitions expose semantic surfaces, selection pairs
and errors for SwayNC. SwayNC restyles with `swaync-client -rs`;
Rofi's `colors-rofi.rasi` is read on every launch, so it needs no reload.

Four components are templated: **cava**, **Starship**, **Vesktop** and **Zen**.
Edit their `<name>.in` files, never the rendered copy or its symlink. cava and
Starship have no include mechanism. cava uses `horizontal_gradient`: cava
0.10.7 corrupts the heap on a vertical `gradient`, even with native themes; a
running cava gets `SIGUSR2`, which reloads colours only. **btop** retains the
`pywal` theme name and uses its native theme directory and `SIGUSR2` hot reload
(the same as Ctrl+R in btop 1.4). cava, Starship and btop use primary tones and
container pairs for their decorative ramps. **fastfetch** resolves its key colours and
logo through ANSI indices; **bat** uses `--theme=ansi`, including man pages
when CachyOS uses it as `MANPAGER`.

**Ghostty** includes `wal/ghostty-colors` through `config-file = ?colors`.
Its script sends `SIGUSR2` to reload the configured palette, then writes
OSC 104/110/111/112 resets to writable, user-owned numeric ptys. These clear
old indexed-colour, foreground, background and cursor overrides. pywal's
OSC 4 overrides take precedence over the configured palette, so any window
that received them would keep them. The resets let the palette reloaded by
`SIGUSR2` show in open terminals. Each write has a one-second timeout;
`WAL_PTS_DIR` points tests at fake ptys. ncurses applications also reset indexed
colours when rebuilding their screens.

ANSI green stays green on every palette, so programs drawn entirely in it,
cmatrix and tty-clock, barely change with the wallpaper. Fish aliases run
them through `scripts/theming/accent-run.sh`, which sets slots 2 and 10 to
`primary` with OSC 4 on that program's terminal only and resets just those
slots (OSC 104;2;10) when it exits. It registers the terminal as
`$XDG_RUNTIME_DIR/dotfiles/accent-ptys/<pid>`; after its resets, the Ghostty
script runs `accent-run.sh --refresh`, which re-applies the new accent to each
registered pty its process still has as stdin and drops every other entry.

Ghostty's translucent window uses `ghostty/blur.css`: GTK 4.24 leaves its
ext-background-effect blur region empty unless the toplevel has a
`backdrop-filter`, which Hyprland honours. Ghostty's `background-blur` speaks
KDE's protocol and does nothing here.

**Neovim** gets `wal/colors-wal.vim` from `nvim/apply_wal_colors.sh`, which
renders the layout the retained `pywal16.nvim` plugin expects. When that file
is absent, LazyVim uses tokyonight. The script re-applies the scheme over
`$XDG_RUNTIME_DIR/nvim.<pid>.0` sockets with bounded `--remote-expr` calls,
never sending keys. The plugin does not set `g:colors_name`, so the plugin
configuration records it in a `ColorScheme` autocmd. Instances whose user
chose another scheme are left alone.

**Vesktop** renders `vesktop/pywal.theme.css.in` into `wal/vesktop.theme.css`.
Enable the tracked `vesktop/themes/pywal.theme.css` link once in Vencord's
Settings > Themes. It recolours surfaces, borders, scrollbars and brand fills,
leaving Discord's text variables alone. The base clamps OKLCH lightness to
0.21–0.26 with capped chroma; the primary accent is clamped to the brand
lightness expected by white button labels. Vesktop watches the themes
directory rather than the symlink target, so `touch -h` on the link recolours
open windows.

**Zen** renders `zen/userChrome.css.in` into `wal/zen-userChrome.css` with the
same base clamp and a lighter primary accent for tabs and focus rings. Its
script finds the launched profile via the `[Install…]` `Default=` entry in
`~/.zen/profiles.ini`, links `chrome/userChrome.css` to the cache and enables
`toolkit.legacyUserProfileCustomizations.stylesheets` in `user.js` once. It
repoints an earlier link to this cache but leaves another user stylesheet
alone. Private and unsynced windows retain Zen's own look. The CSS overrides
inline gradients on `.zen-browser-generic-background`, sets the open address
bar's `--zen-urlbar-background-base`, and pins toolbar text to dark-mode white.
Zen reads the stylesheet at startup; a new palette appears at the next launch.

**eww** renders `wal/eww-colors.scss`, imported by relative path from
`eww/eww.scss`. It does nothing without eww and reloads a running clock through
`scripts/desktop-clock/desktop-clock.sh` only when the colours change. See
`desktop-clock.md`.

**Spotify** retains the tiny `spicetify/Themes/Pywal/` theme on its stock
layout. `color.ini` links to `wal/spicetify-color.ini`, computed with
`wal_oklch` and the primary role; text stays Spotify's white and grey. The
script runs `spicetify -n refresh` only for the selected Pywal theme on an
unpacked client. It shares the patch lock with `scripts/spotify/launch.sh`;
a detached waiter refreshes after an in-progress patch finishes.
`spicetify/Extensions/pywal-live.js` rereads `colors.css` every three seconds
while the window is visible and adopts it as a constructed stylesheet, since
a head `<style>` loses to Spicetify's body stylesheet. The installer runs
`scripts/spotify/spicetify-theme.sh` to select the retained theme and extension
in untracked config. First loading the extension requires `spicetify apply`
and a Spotify restart.

## Strata

`strata/apply_wal_colors.sh` renders `wal/strata-theme.toml` with the shared
fallback before matugen has run. The tracked `strata/themes/tokyo-night.toml`
link replaces the bundled default, so fresh installs use the palette without
setup. Strata's documentation names Azure Glow as the default, but fresh
settings select `tokyo-night`; Azure Glow is the fallback for an unknown saved
theme. The custom theme appears as **Wallpaper** under Your themes, with
`name = "Wallpaper"` and fourteen hex colours including five syntax colours.
Users can still choose another theme.

The base is clamped to a dark or light band. Foregrounds remain readable on
the base and surface, and text on muted and highlight. Its accent comes from
`primary`; destructive actions stay red. GTK4 CSS belongs to the GTK theme
managed by nwg-look; `gtk-4.0/settings.ini` remains rendered machine state.

Strata hard-codes JetBrains Mono, so a fontconfig rule scoped to its
`io.github.lgse.Strata` application ID maps that family to `options/font`.
The rule is read at startup.

Strata reads themes only at startup and has no live reload (upstream #1620).
Normal windows exit with the last window; an idle `--portal` chooser exits
about two minutes after its last dialogue. Open windows and an idle chooser
keep the old palette until the process exits. The hook writes cache files
and never launches or restarts Strata.

## The way back

The `theming-pywal` tag marks the earlier configuration; `theming-matugen`
marks the migration merge. To return to pywal, revert that merge, reinstall
the generator and regenerate from the current wallpaper:

```bash
git revert -m 1 theming-matugen
paru -S python-pywal
wal -n -i "$(readlink -f ~/.cache/current_wallpaper)"
~/.config/scripts/theming/apply-wal.sh
hyprctl reload
```

Run this from the live configuration checkout. Reload Hyprland after the
revert because it rewrites Lua configuration. The cache directory and
component output filenames are unchanged, so the earlier scripts can consume
the regenerated palette.
