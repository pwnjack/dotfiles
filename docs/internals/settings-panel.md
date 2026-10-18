# Settings panel

Moved verbatim from `CLAUDE.md` so the agent instructions stay short. `CLAUDE.md` keeps the rules that must hold on every edit; this file has the reasoning and the traps.

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
GTK `settings.ini` files, Kvantum, `xdg-mime` into `mimeapps.list`, `powerprofilesctl`, hypridle's marked suspend listener and
PipeWire through `pactl` (Sound: ports and the card profile; devices, volume
and per-app routing live in the sound popover); `docs/settings-panel.md` describes each and its
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
and the schedule variables, and rolls file changes back on reload failure. Night light state
still goes through `nightlight.sh`. Writes to files the machine-state overlay renders (options, GTK, `mimeapps.list`, `swaync/config.json`, the night-light variables) run `overlay.sh sync` afterwards so the change is recorded as an override; hypridle's values go to `~/.local/state/hypr/hypridle.conf`, which the tracked `hypridle.conf` sources. See `state.md`. Theme colours come from the shared palette
loader at launch, including `SETTINGS_ERROR` from `wal_role error` for alerts.
The QML fallbacks match the loader's matugen surfaces, text, accent pair and error.
See `docs/settings-panel.md` for measurements and checks.

Appearance's Palette section has three option selects: `theme-scheme`,
`theme-contrast` and `theme-prefer`. A `theme-*` save or reset resolves
`${XDG_CACHE_HOME:-~/.cache}/current_wallpaper` before writing; a missing image
asks the user to change the wallpaper once first. The backend runs
`scripts/theming/generate-palette.sh <resolved-image>` with its default output
directory, then `scripts/theming/apply-wal.sh`. Only generation failure rolls
the option back and regenerates the previous choice; the panel shows the last
stderr line. Applying components is best effort after publication: its failure
keeps the new option and palette and the save succeeds. The panel has no way
to show a non-fatal save message, so it swallows component failures.
This deliberately bypasses `wall.sh`, whose transition delay, unbounded lock
wait, failure toast and component failures belong to wallpaper changes. The
generator has its own bounded publication lock and a timeout for each matugen
pass. The panel reads the new colours on its next opening.

The Network, Date & Region and Startup pages work as follows. **Network** reads libnm through `nm.js` with the pure
`network.mjs` model; `nmcli monitor` and a 20 s rescan run only while the page is
visible, and `PROTON_MODE = "app"` means the panel shows Proton VPN and opens its app
rather than toggling a profile the app deletes. **Date & Region** writes time zone, NTP,
language and formats through polkit-authorised `timedated`/`localed` calls in `dbus.js`;
`authPending` hides the panel so the polkit dialog is reachable (`authHidesPanel`).
The 12/24 h clock is `options/clock`, rendered by `scripts/waybar/clock-format.sh` into
the `~/.local/state/waybar/clock.jsonc` Waybar include, and hyprlock and the desktop clock (`desktop-clock.md`) read the option.
**Startup** lists `autostart.lua` and manages XDG autostart entries by uwsm's generator
rules; `~/.config/autostart` is per-machine and gitignored, and disabling a system entry
writes a minimal `Hidden=true` override. Panel writes reach `panel-request.sh -` on stdin,
never in argv, so passwords stay out of `ps`.

**Calendar** shows the iCloud account (sign-in over stdin to `scripts/calendar/setup.sh --sign-in --stdin`, Sync now, a two-press Sign out) and one switch per calendar, then the catalog's Events and New events rows (`calendar-declined`, `calendar-default`, `calendar-alert`, `calendar-duration`). `shell.qml` reads `calendarStatus` every 5 s only while the page is visible. A save of `bar-agenda` (the Bar page's Calendar row) or any `calendar-*` option runs `scripts/calendar/sync.sh --render` and rolls the option back if that fails; see `calendar.md`. **Startup** draws the catalog's At login switches first, then the app lists.

**Sound** draws the catalog's Output and Input sections (their headings follow the current default device through `titleFrom`), then a Devices list: a name field and a show switch for each output and input, which the sound popover reads. `shell.qml` runs `soundDevices` when the page opens, after any write and on the `audioEvents` parser's sink, source, card and server lines (one 300 ms debounce, no second `pactl subscribe`). `SoundView.qml` draws a copy of the reply that it keeps while a name field has focus, because replacing a Repeater's array rebuilds its delegates and wipes typed text. The current default device's switch is disabled.

**Devices** lists wireless peripherals from `scripts/devices/devices.sh`, the one reader shared with Waybar's battery module and the low-battery toast; `shell.qml` runs it on open and every 10 s only while the page is visible, and `alert` is defined once, in the script.
