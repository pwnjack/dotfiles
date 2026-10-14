# Desktop clock

An [eww](https://github.com/elkowar/eww) widget: the time in large bold type with the date beneath it, at the bottom right of the wallpaper (120 px in from the right, 50 px up, 500 px wide) on the `bg` layer, in the palette foreground at 0.8 opacity. It is the repo's only eww window.

## Pieces

- `eww/eww.yuck` and `eww/eww.scss` are tracked and static. Everything that varies is generated into `~/.cache` and imported by the stylesheet, so a setting or wallpaper change never dirties git.
- `scripts/desktop-clock/desktop-clock.sh` is the only thing that runs `eww open`, `eww close` or `eww reload` for the clock.
  - `start` runs at login from `scripts/hyprland/startup.sh` and opens the clock when it is enabled and not already open.
  - `apply` re-reads the options, then closes the clock when it is disabled, or closes it, reloads eww and opens it again with the current format, font and monitor. The settings panel runs it after the toggle, the font or the 12/24 h choice changes, and after a new main display is chosen.
  - `reload` recolours or restyles a running clock and never starts one.
  - It does nothing when `eww` is not installed.
- `eww/apply_wal_colors.sh` follows the rules in `theming.md`: it renders `~/.cache/wal/eww-colors.scss` (`$background`, `$foreground`) from the shared palette loader, with the fallback palette before matugen has run, and asks the owner script to reload a running clock only when the colour changed. `--no-reload` renders and stops.

## Options

| File | Meaning |
|------|---------|
| `desktop-clock` | `enabled` (tracked default) or `disabled` |
| `desktop-clock-font` | font family, default `Adwaita Sans` |
| `clock` | `12h` shows `%I:%M %p`; anything else keeps `%H:%M` (the same option as the Waybar clock) |
| `mainmonitor` | when non-empty, the monitor the clock opens on; empty means monitor 0 |

The date is always `%A - %d/%m`, with the day named in the session's `LC_TIME` language. The panel rows are in Appearance under "Desktop clock" (`appearance.desktop-clock`, `appearance.desktop-clock-font`).

## Decisions and traps

- **The time costs no process.** eww's built-in `EWW_TIME` (present in the installed 0.6.0 package, whose `--version` still prints 0.5.0) feeds `formattime(EWW_TIME, time_fmt)`, so there is no `date` spawn per tick. The date is the one `defpoll`, running `date` once a minute as the old clock did: `formattime` names the weekday in English whatever `LC_TIME` says, and `date` follows the session's locale.
- **A missing option is its tracked default.** At the first login `overlay.sh sync` renders `options/` in the background, possibly after `startup.sh` has run the owner script, so the script reads `defaults/options/<key>` when the live file is absent; the clock is on by default.
- **The format is a window argument.** `time_fmt` is passed with `eww open --arg`, so changing the 12/24 h choice means closing and reopening the window, which `apply` does. A reload keeps the arguments of a window that is still open.
- **The font is a generated SCSS partial, not an inline style.** `~/.cache/eww/font.scss` defines `$clock-font`, and `eww.scss` uses it in both `font-family` rules. The value is user text from the panel, and SCSS would evaluate `#{…}` in a quoted string or let a quote end it, so a name containing anything but letters, digits, spaces and `. _ + -` is ignored in favour of the default, with a note on stderr. An inline `:style` would have needed the same escaping in yuck.
- **Tracked symlinks are not used.** The stylesheet imports `../../.cache/wal/eww-colors.scss` and `../../.cache/eww/font.scss` by relative path, as the old config did. Both files are written before eww first parses the stylesheet: the owner script renders the font partial and, if it is missing, the colour partial, so the import cannot dangle even though the apply script does nothing without eww. Like Waybar's and SwayNC's stylesheets, the relative path assumes the cache sits beside the config directory (`~/.cache` next to `~/.config`); with an `XDG_CACHE_HOME` elsewhere the scripts would write where the stylesheet does not look.
- **eww names monitors by model.** `eww open --screen` accepts an index or a model such as `ROG PG279Q`, not a connector such as `DP-1`. `options/mainmonitor` is a connector, so the owner script looks its model up with `hyprctl monitors -j`. Nothing guesses: an unknown connector, two monitors of the same model (indistinguishable by name) and an empty preference all leave the clock on monitor 0, and a monitor eww rejects is retried without `--screen`.
- **Disabling stops the daemon.** The clock is the daemon's only window, so `apply` kills it when it closes the clock and nothing stays resident. `eww kill` only queues the shutdown and the daemon keeps answering `ping` while it exits, so `apply` holds the lock until `ping` fails; otherwise a quick re-enable would reopen the clock on a daemon that is about to vanish.
- **A rejected reload is a failure.** eww returns a stylesheet or config it cannot load to the client, and the owner script passes that on, so the panel shows the error rather than a stale clock. `apply_wal_colors.sh` exits non-zero for the theming driver and leaves `~/.cache/wal/.eww-reload-failed`, so the next palette run retries the reload even when the palette is unchanged.
- **Every eww call has its stdio detached,** and the lock file descriptor is closed for it. The daemon forks from the first call; if it kept the caller's pipes, the settings panel (which waits for them to close) and `wall.sh` (which reads stderr to the end) would stall until it exited, and a daemon holding the lock would block every later call.
- **Do not follow the logs in a script.** `eww logs` tails the log file for ever.

## Tests

`scripts/desktop-clock/test-desktop-clock.sh` runs both scripts against a stub `eww` and `hyprctl` with a throwaway `HOME`, config and cache. `test/test-theming.sh` runs the apply script with `eww` stubbed, so no test touches the real daemon.
