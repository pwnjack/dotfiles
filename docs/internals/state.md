# Machine state (settings overlay)

Settings that a machine changes (options, GTK and Qt settings, default applications, the notification centre's config, the night-light schedule) are not tracked files. The repo tracks the defaults; each machine's differences live outside it, so changing a setting never dirties git and a pull never overwrites one.

## Layout

- `defaults/` holds the tracked default of every overlay file, at the path it has in `~/.config` (`defaults/options/browser`, `defaults/gtk-3.0/settings.ini`, `defaults/hypr/hyprsunset.conf` and so on). Targets are discovered from this directory; no script lists them.
- The live file sits at the same path without `defaults/` (`options/browser`). It is rendered, ignored by git and never committed. Everything reads it as before.
- `${XDG_STATE_HOME:-~/.local/state}/dotfiles/overrides/<live path>` holds this machine's differences from the default, in the file's own format. A key the machine removed is recorded in `overrides/<live path>.removed`.
- `.../dotfiles/last/<live path>` is the file as last rendered; the next sync compares the live file with it to see what changed since.
- `.../dotfiles/overlay.lock` serialises syncs.

`options/wallpaper` stays a tracked symlink and is not part of the overlay.

## Formats

The format follows the path: `options/` is a directory with one value per file; `*.json` is compared per top-level key; `hypr/*.conf` is Hyprlang `$variable = value` lines; everything else (GTK and Qt settings, `mimeapps.list`) is an INI file compared per section and key.

Values are compared exactly. An option file's trailing newline counts. JSON is compared by the JSON text of each top-level key and rendered with `JSON.stringify(..., 2)`, so the first render of `swaync/config.json` may reformat it without recording an override.

In a Hyprlang file a value ends at a `#` comment (`##` is a literal `#`), and a replaced line keeps its comment.

## Sync

`scripts/state/overlay.sh sync` runs, under the lock, for each target:

1. Harvest: a live value that differs from `last/` is a change made here (by a panel, an app or `echo`). It becomes an override, unless it equals the default, in which case the override is dropped. A key missing from the live file always drops its override. For INI and JSON files the deletion is also recorded in `.removed` and the key stays absent. For `options/` and Hyprlang variables a missing key is a reset, so deleting `options/<key>` returns it to the default.
2. Render: default plus overrides is written to the live file and to `last/`.

An override equal to its default never survives a sync, so promoting a value to the default needs no clean-up. To make a value the repo default, edit the file under `defaults/` and commit it.

`overlay.sh check` reports an overrides file that does not parse. The script does nothing in a tree without `defaults/`, refuses to run unless its tree is `~/.config` (or `OVERLAY_STATE_DIR` is set, which tests use), and needs `node` and `flock`.

Sync runs:

- at login, from `scripts/hyprland/startup.sh`, in the background so it never delays the lock on autologin;
- after a pull or branch switch, from the `post-merge` and `post-checkout` hook;
- on install, with `--replace <backup dir>` (or `--no-backup`, which copies nothing). A live file that predates the overlay is copied to the backup and replaced. `--replace` never deletes before rendering, keeps recorded overrides, and acts only on keys that `defaults/options` declares: per-machine keys with no default (`calendar-*`, `capture-*`) stay and are adopted;
- from the settings panel after each write to a rendered file.

Some writers (the calendar and capture Quickshell apps, `echo firefox > options/browser`) write live files directly. The next sync records them; nothing is lost in between.

## Derived files

After each sync `scripts/state/derived.sh` renders what is computed from options into `~/.local/state`, where tracked relative symlinks point:

- `hypr/config/hardware/primary.conf` links to `~/.local/state/hypr/primary.conf`, the `$monitor =` line for Hyprlock, from `options/mainmonitor` (empty means every monitor).
- The font: `scripts/fonts/apply-font.sh --includes` renders `rofi/options/font.rasi` and `ghostty/font` (tracked symlinks) and `~/.local/state/waybar/font.css`. Waybar imports the last by relative path from `style.css`, because its style watcher ignores symlinked imports (the same reason as `colors-waybar.css`).

## Hypridle and hyprsunset

`hypr/hypridle.conf` is tracked and never written. It defines `$lock_timeout` and `$dpms_timeout`, then `source`s `~/.local/state/hypr/hypridle.conf`, which the settings panel writes and which may redefine them and add a suspend listener. The path is fixed because Hyprlang does not expand `XDG_STATE_HOME`.

`hypr/hyprsunset.conf` is rendered from `defaults/hypr/hyprsunset.conf`. Its schedule is four `$variables` (times and temperatures) that the panel's Power page overrides; the profiles refer to them. Only variables the default declares are kept. Edits to the live file outside the `$` lines are replaced on the next render, so change the default instead. `nightlight.sh` resolves profile temperatures through the variables.

## Pull transition

The merge that moved these files into `defaults/` makes git delete the old tracked live files, and `post-merge` renders them again. A pull refuses if one of them has local edits. Recovery: move the files aside, pull, move them back, then run `bash ~/.config/scripts/state/overlay.sh sync`. Adoption records the differences as overrides.

`hypr/hypridle.conf` is the exception. Before the overlay the panel wrote timeouts into that tracked file, so a machine may have it modified, and the pull refuses. Note the timeouts, discard the local edit with `git checkout -- hypr/hypridle.conf`, pull, then set them again in the panel's Power page (or write `$lock_timeout = N` and `$dpms_timeout = N` lines, and any suspend listener, into `~/.local/state/hypr/hypridle.conf`). Moving the old file back would drop the new `source` line, and sync never adopts it.

## Doctor

`check_state` derives its targets from `defaults/`. It reports a live file that is not rendered, is tracked, or is not ignored, and a tracked `defaults/` path matched by an ignore rule. It warns about an overrides file that does not parse, and when `XDG_STATE_HOME` differs from `~/.local/state`, because hypridle's `source` path is fixed.
