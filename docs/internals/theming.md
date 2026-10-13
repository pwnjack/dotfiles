# Pywal colour flow and per-component theming

Moved verbatim from `CLAUDE.md` so the agent instructions stay short. `CLAUDE.md` keeps the rules that must hold on every edit; this file has the reasoning and the traps.

Wallpaper image -> `wal -i` -> `scripts/theming/apply-wal.sh` fans the palette out to every consumer. `hypr/apply_wal_colors.sh` renders `colors-hyprland.lua` for Hyprland and `colors-hyprland.conf` for Hyprlock; the tracked `colors.lua` and `colors.conf` files are symlinks to those cached outputs. Changing the wallpaper via `scripts/hyprland/wall.sh` triggers this pipeline automatically. Generated state lives under `~/.cache` (`current_wallpaper`, `wal/colors-hyprland.lua`, `wal/colors-hyprland.conf`, `wal/rofi-wallpaper.rasi`, `wal/colors-rofi.rasi`, `wal/colors-waybar.css`, `wal/ghostty-colors`, `wal/thunar-gtk.css`, `wal/strata-theme.toml`, `wal/cava-config`, `wal/btop.theme`, `wal/starship.toml`, `wal/vesktop.theme.css`, `wal/zen-userChrome.css`, `wal/spicetify-color.ini`, `waypaper-config.ini`); the repo tracks only symlinks to it, so wallpaper switches never dirty git.

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

## Strata

`strata/apply_wal_colors.sh` renders `~/.cache/wal/strata-theme.toml` through
the shared palette loader, with fallback colours before pywal has run. The
tracked `strata/themes/tokyo-night.toml` symlink replaces Strata's bundled
default theme, so a fresh install uses the palette without setup. Strata's
own docs name Azure Glow as the default, but a fresh `settings.toml` selects
`tokyo-night` (Azure Glow is only the fallback for an unknown saved theme);
if upstream changes that, "Pywal" still appears under Your themes. Users can
still choose another theme in Strata. The TOML file contains `name = "Pywal"`
and fourteen hex colours, including five syntax colours. Its base is clamped
in OKLCH into a dark or light band; foregrounds remain readable against the
base and surface, and text against muted and highlight. Thunar's GTK3 hook
and import remain available. GTK4 CSS is left to the GTK theme managed by
nwg-look; `gtk-4.0/settings.ini` remains rendered machine state.

Strata hard-codes JetBrains Mono, so a fontconfig rule scoped to its prgname
`io.github.lgse.Strata` maps that family to `options/font`. This is Strata's
application ID, not `strata`, and it reads the rule at startup.

Strata reads themes only at startup. Normal windows exit with the last
window; an idle `--portal` chooser exits about two minutes after its last
dialog. Open windows and an idle chooser keep the old palette until that
process exits. The hook writes only cache files and never launches or
restarts Strata.
