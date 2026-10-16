# Settings panel

Super+I and Waybar's settings button open `quickshell/settings-panel/shell.qml`.
The panel starts a fresh process, renders its frame, then reads all settings
asynchronously into a small session snapshot. Tab switches and search use those
values immediately, without starting another helper. Edits refresh the snapshot;
closing discards it, so reopening always reads current values. Escape, Close,
clicking outside, or Super+I closes it.
Once pending saves finish, the process exits. Failed saves keep the error visible
by reopening the panel. Text fields apply with Return or their Apply button, which appears while the text differs from the saved value; sliders save on release.

`catalog.json` is the only list of settings: 124 rows on 17 pages (16 in the
sidebar, plus About), with search, editable display cards and per-row resets.
Pages sit in five sidebar groups, and rows sit in titled sections inside each
page, one line each: label on the left, control on the right. Reload Hyprland,
Restart bar and Update system… live in the title bar's ⋯ menu; Restart bar also
appears as a button in the Bar page's Layout section, and Update now in Default
Apps' Launcher & updates section. Things another surface already owns stay
there: the keybind cheatsheet (Super+H), Do Not Disturb, output volume, mute and
per-app volume (SwayNC), running updates (the update card; the panel only
chooses whether the bar shows the module), screenshot and recording options
(the capture bar) and picking wallpapers (the carousel; the panel only holds
the random-wallpaper-at-login switch and palette options). The palette is
read through `scripts/theming/palette.sh` on every launch.

## Pages

| Page | Group | Rows | Sections |
| --- | --- | --- | --- |
| Appearance | look | 23 | Style, Themes, Palette, Fonts, Desktop clock, Cursor, Window style, Transparency & effects |
| Bar | look | 14 | Layout, Clock & workspaces, Modules (see [Bar](#bar)) |
| Windows | look | 10 | Tiling, Focus, Advanced |
| Animations | look | 8 | General, Speed |
| Notifications | look | 7 | Position, Timing, Size |
| Network | connectivity | 1 | Its own view: Wi-Fi, Wired, VPN (see [Network](#network)) |
| Devices | connectivity | — | Its own view: wireless peripherals (see [Devices](#devices)) |
| Displays | hardware | 1 | One card per output, plus Options (see [Displays](#displays)) |
| Sound | hardware | 6 | Output, Input |
| Power | hardware | 9 | Power mode, Lock & sleep, Wake screen, Night Light |
| Keyboard & Mouse | input | 15 | Keyboard, Mouse, Touchpad, Pointer |
| Accessibility | input | 2 | Vision |
| Date & Region | system | 5 | Date & time, Language & formats (see [Date & Region](#date--region)) |
| Calendar | system | 4 | Its own view (account, sync, calendars), then Events and New events (see [Calendar](#calendar)) |
| Startup | system | 3 | At login, then the autostart lists (see [Startup](#startup)) |
| Default Apps | system | 16 | Applications, File types, Launcher & updates |
| About this machine | system | — | Opened from the account card under the sidebar |

## Palette

Appearance's Palette section controls how matugen draws colours from the
current wallpaper:

- **Scheme:** Tonal spot (default), Vibrant, Expressive, Content, Fidelity,
  Neutral, Monochrome, Rainbow or Fruit salad.
- **Contrast:** Reduced (−0.5), Standard (0, default), Medium (0.5) or High (1).
- **Source colour:** Most saturated (default), Least saturated, Darkest,
  Lightest or Brightest.

These save `options/theme-scheme`, `options/theme-contrast` and
`options/theme-prefer`. Each change regenerates the palette for the current
wallpaper and recolours the desktop. The panel itself picks up the new colours
on its next opening. If generation fails, the panel restores the previous
option and regenerates it, showing the last diagnostic line. Once generation
succeeds, component reload failures keep the new option and palette. If no
current wallpaper is recorded, change the wallpaper once before using these
controls.

Terminal red, green and the other chromatic ANSI colours always use tonal
spot at standard contrast, with the same wallpaper and source-colour choice.
Background, foreground and desktop colour roles follow the selected scheme
and contrast. Error messages use matugen's error colour.

## Implementation

- Layout is data. Each category has a `group` (`look`, `connectivity`,
  `hardware`, `input` or `system`, in that sidebar order; the categories array
  is the sidebar order, a gap opens where the group changes, and the panel
  opens on Appearance, the top entry) and ordered `sections`
  (`{id, title, footer?, actions?}`, where each action is `{label, action}` and
  the action is `reload`, `waybar` or `update`). Each row names its `section`.
  A slider may add `ends` (two end labels shown instead of the value) and
  `invert` (drawn mirrored, so right means faster for Hyprland's animation
  durations; stored values are unchanged). Any row may add `dependsOn`, the id
  of a toggle on the same page; the row is dimmed and disabled while that
  toggle is off. `pages.mjs` turns the catalog into sidebar entries and drawn
  sections, and its `validateCatalog` enforces every rule above.
  `test/catalog.mjs` runs that check on the real file and freezes the set of
  row ids, because ids are API; `test/search.mjs` evaluates the real
  `visibleRows` binding, which the QML tests stub. Search matches section
  titles too, and a title made plainer keeps its old wording in `keywords`.
  `backend.js` ignores all of these keys.
- A category with `"placement": "footer"` (only `about`) has no sidebar entry;
  the account card pinned under the list opens it. The card shows the avatar
  (`~/.face`, else AccountsService's icon file; files only, no D-Bus, so the
  every-open read cannot start or wait on accounts-daemon), the name, the host
  and two quiet summary lines (OS and kernel, Hyprland and uptime). That
  summary is part of every read; the About page asks for `about: "full"`, which
  adds the install date (first line of `pacman.log`, which survives snapper
  rollbacks, falling back to the root filesystem's creation time), the last
  completed full upgrade (from the log's last 256 KiB), CPU, GPUs (`lspci`),
  memory, root storage in decimal GB (GIO `filesystem::used`, as `df`) and the
  board or laptop model. Parsing and formatting live in the pure `about.mjs`,
  shared by the backend, QML and Node; every field is optional and a missing one
  hides its row.
- `catalog.json` owns setting metadata, accepted ranges and dropdown choices.
  Each category's `icon` is a hex codepoint of a Material Design glyph in
  Symbols Nerd Font (`ttf-nerd-fonts-symbols`), drawn in the nav rail and beside
  the page title. It is text, so it follows the selection and palette colours —
  the Papirus symbolic icons would not (see the night light notes). Look names
  up in the font's cmap (`md-<name>`) rather than retyping glyphs.
- `SettingsView.qml` and `SettingControl.qml` build only visible category/search
  rows. Reads and writes never run synchronously on the QML thread. The first
  rows appear with their real values; loading never inserts/removes a layout row.
  Dropdown popups, option rows and selection highlights use the panel palette.
- `request.js` runs the GTK-free GJS backend for one JSON request and exits.
  `panel-request.sh` holds a lock across the complete request. Arguments stay
  argument arrays, including text containing quotes or shell metacharacters.
- `persist.js` and `hyprctl.js` own the shared persistence layer. Apply/save
  waits for Hyprland's `ok`; failed writes reload the saved config;
  resets remove just the selected override and reload the actual Lua defaults.
  Overrides are per-machine state in `${XDG_STATE_HOME:-~/.local/state}/hypr/overrides.lua`,
  never a tracked file, so using the panel leaves git clean; `hyprland.lua` loads
  it last if present and skips it, with a notification, if it fails to run.
- The backend writes hypridle's timeouts to `~/.local/state/hypr/hypridle.conf`
  (sourced by the tracked `hypridle.conf`) and the night-light `$variables` in
  `hypr/hyprsunset.conf` (the rendered live file; the tracked default is
  `defaults/hypr/hyprsunset.conf`), preserving unrelated
  content, and restores files if applying them fails. SwayNC retains unrelated
  keys. Night light liveness uses `nightlight.sh`, never an identity getter.
- Rows whose value lives in a file the machine-state overlay renders (`options/`,
  GTK and Qt settings, `mimeapps.list`, `swaync/config.json`, the night-light
  variables) write the live file and then run `scripts/state/overlay.sh sync`, so
  the change is recorded as this machine's override and never reaches a tracked
  file (see `docs/internals/state.md`).
- Rows may declare `choices` instead of fixed `items`. An enumerator in
  `backend.js` lists what is installed now (GTK, icon, cursor and Kvantum
  themes, power profiles, apps per MIME type); every read returns the list with
  the value and every write is validated against the same enumerator, so the
  dropdown and validation cannot disagree and no list of names is tracked.
  GTK's built-in themes (Adwaita, HighContrast, HighContrastInverse) are
  libgtk resources with no directory and are added explicitly.
- Text rows may declare `check`: `xkb-layout`/`xkb-variant`/`xkb-options`
  (checked against `localectl list-x11-keymap-*`, because a rejected keymap
  leaves Hyprland on the old one with only a log line), `font` (`fc-list`) and
  `command` (on `PATH`). `optional` rows accept an empty value; app rows with
  `reload` reload Hyprland, which reads `options/` at parse time (and exports
  `BROWSER`, `TERMINAL`, `EDITOR` and `VISUAL` from them). The File manager row
  also runs `scripts/settings/file-manager.sh` and the Terminal row
  `scripts/settings/terminal.sh` (xdg-terminal-exec's list). A layout
  reset is refused while a variant override exists.
- Sources: `gtk` writes gsettings, and for rows that declare an `ini` key also
  both `settings.ini` files (GTK 3 on Wayland reads some keys from
  each; Text Size is gsettings-only); `kvantum` edits `theme=` under
  `[General]`; `mime` writes `xdg-mime default` into
  `mimeapps.list`, only for the row's types the chosen app declares or declares a
  parent of (never via `application/octet-stream`, which everything is),
  falling back to the row's first type when it declares none, and restores
  the file byte-for-byte on failure; `powerprofile` drives
  `powerprofilesctl`; the `idle` source adds, retimes and removes only the
  suspend listener it marked, and refuses to change a hand-written one;
  `pulse` (`pulse.js`) serves the six Sound rows from four `pactl -f json`
  reads (`info`, `list sinks/sources/cards`) made once per request in
  parallel. PipeWire's pulse server reports `card: null` on every sink, so a
  sink's card is the one whose name equals `properties["device.name"]`. Sink
  monitors are sources too and are left out of Input Device; unplugged ports
  and profiles without a sink (`off`, input-only) are left out of the
  choices. With no valid default, the device selector keeps its choices so
  the panel can recover, while ports, profile and level report the error.
- Live refresh: rows tagged `"live": "audio"`, and the unsearched Displays
  page, are re-read while they are on screen and nothing else is.
  `shell.qml` runs `pactl subscribe` only while an audio row is visible and
  counts only `sink`/`source`/`card`/`server` events (`sink-input` and
  `client` fire for every stream and notification); Displays listens to
  `Hyprland.rawEvent` monitor and reload events. Reads are debounced
  (300 ms), single-flight, limited to the tagged rows, dropped while a write
  or full read runs, and never overwrite the control being dragged or
  opened. Waking a suspended sink is a real `change on sink`, so the first
  sound after silence costs one or two reads while the Sound page is shown.
  The IPC call that switches page is `page`, not `show`: qs parses `show` as
  its own `ipc show` subcommand even inside `ipc call`.
- `hyprctl getoption -j` names the value field after its type (`bool`, `int`,
  `float`, `str`, `css`, `custom`); `set` only says whether the config assigns the
  option and is never a value. The Lua provider rejects legacy hyphenated
  names: use `input:touchpad:tap_to_click`, not `tap-to-click`.
- `gjs` is an explicit dependency of the backend: `settings-panel.sh` refuses
  to start without `qs`, `gjs` and `flock`.

## Displays

Per-machine display rules live outside the repo in
`${XDG_STATE_HOME:-~/.local/state}/hypr/monitors.lua`, one `hl.monitor()` per
output, written only by the Displays page. Edit file opens it in
`options/editor`; Hyprland does not watch it, so run Reload Hyprland after a
hand edit. The tracked `hypr/config/hardware/monitor.lua` keeps its
host-neutral catch-all and loads that file if present, in an environment that
can only record `hl.monitor()` calls; every value must be plain data (keys
are Hyprland's to judge, so a hand-added `vrr` or `bitdepth` applies), and
rules are applied only once the whole file has run, so a broken file leaves
the catch-all and shows a notification. A missing file means all automatic. A line the panel did not
write, or a second line for the same output, locks that output ("edited by
hand"). The main display cannot be turned off (hyprlock draws its password
field there); choose another main display first. While Hyprland loads its config,
`hl.monitor()` does not raise for a value it rejects (transform 9, a mode it
cannot parse): it records a config error and skips that one rule, so such a
hand edit shows in Hyprland's error banner instead.

Edits are staged on each card and one Apply sends them together. Apply arms
`systemd-run --user --collect --unit=settings-display-revert --on-active=20
… hyprctl reload`, then `hyprctl eval`s the new line, confirms the guard is
still armed, and only then records the pending change in
`$XDG_RUNTIME_DIR/settings-panel/display-pending.json`. The panel's banner
counts down 15 s; Revert, timeout, Escape and Close reload Hyprland (the
state file only changes on Keep, so a reload restores the last kept layout)
before disarming the guard. Keep writes the evaluated line while the guard is
still armed, stops it, and reloads so the live layout always equals the saved
file. If the panel dies or its screen goes dark, the guard reverts at 20 s.
While a change is pending every other setting and button waits, and the backend refuses every request but reads and the
display operations, since a reset or reload would silently undo it.

Verified on DP-1 (ROG PG279Q, 2560×1440) with Hyprland 0.56.2:

- `hyprctl eval 'hl.monitor({ output = "DP-1", ... })'` applies at once
  (143.998 → 119.998 Hz within 1 s); `hyprctl reload` restores the file's rule.
- Apply then nothing: the panel reverts at 15 s. Apply then `kill -9` of the
  panel: the guard reverts at about 21 s. Apply then Close: reverted in about
  140 ms. None leaves a unit, a pending record or a panel process.
- Scales, each accepted by `eval` with `ok` and no config error: `1.25` →
  1.25; `1.3333333333333333` → 1.3333334; `1.5` → **1.6, silently**. Hyprland
  substitutes a nearby scale when the logical size is not whole, so the panel
  offers only `k/120` scales that divide the staged mode.
- The systemd user manager of the UWSM session carries
  `HYPRLAND_INSTANCE_SIGNATURE`, which the guard inherits when a request has
  none. `systemctl stop` of an unloaded unit says `Unit … not loaded.`

## Probes behind the Network, Date & Region and Startup pages

Probed 2026-09-28 and 2026-09-29 on the author's machine, before those pages
were built.

### Baseline
Full read (every row plus monitors), five runs: 275, 275, 278, 281, 288 ms. Median **278 ms**.

### D-Bus cold start
`gdbus` `Get NTP` + `ListTimezones` (598 zones, 10.9 kB) after 40 s idle: cold **62 ms**, warm **14 ms**.
Both figures include two `gdbus` process starts, so the in-process cost is lower.

### nmcli monitor and scans
`nmcli monitor` prints `NetworkManager is running` once at start, then **nothing** for a
completed `nmcli device wifi rescan` (8 s watched). The list refresh after a scan therefore
comes from the panel's follow-up read (`scanSettle`). The banner line causes one extra
debounced read when the page opens, which is harmless.

### Quickshell stdin
A `Process` with `stdinEnabled: true` that calls `write()` in `onStarted` delivers the line:
the probe printed `got:{"op":"read"}`.

### Waybar include
Waybar 0.15 expands `~` in `include` (`Found config file: /home/you/.local/state/...`) and
merges key by key: with `"format": "MAIN"` in the main file, the trace says
`Option format is already set; ignoring value "PROBE ..."`, while the include's `interval`
was taken. A main `clock` object without `format` therefore takes the include's format.
Decision: **include at `~/.local/state/waybar/clock.jsonc`**. The on-screen check followed on
2026-09-29 (see Measurements).

### Proton VPN
Probed 2026-09-29. `nmcli connection down` on the Proton profile deactivated the tunnel, and
the Proton app then **deleted** both the WireGuard profile and the `pvpn-killswitch-ipv6`
dummy, so there is nothing for `nmcli connection up` to bring back. Traffic kept flowing over
the real IP (the kill switch is not in permanent mode). The app showed a clean "Disconnected",
and reconnecting from the app created a new profile named after the new server.
Decision: **`PROTON_MODE = "app"`** (`network.mjs`): the panel shows the state and opens the
Proton app, and never switches Proton's profile itself.

### Polkit dialog versus the overlay
Probed 2026-09-29: with a panel-shaped Overlay surface up (keyboard focus None), an
interactive `SetTimezone` opened hyprpolkitagent's dialog (Waybar's title read
"Authentication Required") but the dialog was completely hidden behind the overlay and could not
be clicked. Decision: **`authHidesPanel: true`** (`shell.qml`): the panel hides while a prompt
is open. A dismissed dialog returns `org.freedesktop.DBus.Error.AccessDenied: Permission denied`, which
`authError.mjs` maps to "Authentication was cancelled; nothing changed." (checked: the time zone
stayed Europe/Rome).

### Per-user locale
The systemd user manager already has `LANG=en_US.UTF-8` and `LC_TIME=it_IT.UTF-8`, and
`/etc/profile.d/locale.sh` reads `~/.config/locale.conf` only when `LANG` is unset.
Decision: **formats use SetLocale** (system-wide, polkit).

## Network

Reads: libnm through `nm.js` (`NM.Client.new(null)`, about 7.5 ms) for devices, access
points, saved profiles and VPN connections; `network.mjs` is pure and turns that
snapshot into the view (security grouping is under "Network: security rules").
Writes: connect/disconnect, forget, Wi-Fi radio, and new connections. **Advanced…**
opens `nm-connection-editor`; hidden SSIDs, enterprise Wi-Fi, WEP, hotspots and IP/DNS
editing are out of scope.

Live behaviour: while the page is on screen, exactly one `nmcli monitor` runs
(`/usr/bin/nmcli monitor`; pattern `^(/usr/bin/)?nmcli monitor$`) and a 20 s rescan timer
runs. Leaving the page or closing stops both. The monitor prints only a startup banner
and nothing on scans, so the list refresh after a rescan comes from the follow-up read.

Traps:

- **The PSK only travels on stdin.** Panel writes reach `panel-request.sh -` as one JSON
  line on the helper's stdin, never in argv, so a password cannot show in `ps` or a log.
- **A failed new connection is deleted.** A wrong password leaves no half-made profile.
- **`PROTON_MODE = "app"`.** The Proton app deletes its WireGuard profile on disconnect
  and creates a new one per server, so the panel shows the state and opens the app; it
  never brings a Proton profile up or down.
- **Nothing runs when closed:** no `nmcli monitor`, no timer, no panel process.
- `pgrep -f '^nmcli monitor$'` finds nothing: the real command line is
  `/usr/bin/nmcli monitor`.

## Date & Region

Reads `timedatectl show` and `localectl status` (both daemons are socket-activated:
about 100 ms cold). Writes time zone, NTP, language and formats through `timedated` and
`localed` over D-Bus (`dbus.js`), authorised by polkit. Clock format is not system-wide:
`options/clock` (`12h` or `24h`) is rendered by `scripts/waybar/clock-format.sh` into
`~/.local/state/waybar/clock.jsonc`, which Waybar merges through `include`; hyprlock reads
the option too.

Traps:

- **Waybar's clock is English unless its format says `L`.** It ignores both
  `LC_TIME` and its own `locale` option for `{:%a}`-style names; `{:L%a}` is what
  makes the Formats row reach the bar, the way `date` already makes it reach hyprlock.

- **Polkit focus and visibility.** `authHidesPanel` is true in `shell.qml`: a panel-shaped Overlay hid hyprpolkitagent's dialog completely, so the
  panel hides while `authPending` is set and comes back after the answer. A dismissed
  dialog returns `org.freedesktop.DBus.Error.AccessDenied: Permission denied`, shown as
  "Authentication was cancelled; nothing changed."
- **`timedated` cold start.** A first call after idle costs tens of ms more; the zone
  list (598 zones) is read once per full read.
- **The Waybar include** merges key by key and the main file's `clock` has no `format`,
  so the include's format wins; the include path is fixed (`~/.local/state/waybar/`).
- **Formats use `SetLocale`** (system-wide, polkit): a per-user `locale.conf` is not
  effective because the systemd user manager already exports `LANG`/`LC_TIME`.

## Startup

Three sections, in this order: the catalog's **At login** switches (Lock on autologin,
Random wallpaper, Proton VPN), the XDG autostart **Apps**, and **Started by Hyprland**,
which lists what `autostart.lua` starts (parsed, read-only, with **Edit file**). The apps
follow uwsm's generator rules (`autostart.mjs` is pure): later `Show-In` lists win, condition keys parse strictly, and `TryExec` is verbatim.
Changes take effect at the next login; nothing is started or stopped immediately.
`~/.config/autostart` is per-machine and gitignored.

Traps:

- **Generator rules and the minimal override.** Disabling a system entry writes only a
  minimal `Hidden=true` override with the same file name; removing a stub restores the entry.
- **Hand-edited overrides are never deleted.** Only stubs the panel wrote and apps it
  added are removable; a customised override is left alone and a broken one names its file.
- **Never write through symlinks;** a symlinked entry is not edited or replaced.
- **`arch-update-tray` was silently skipped:** its `TryExec` names a program that is
  not installed, so the generator drops it without a message. The page says "Not installed"
  and `doctor.sh`'s `check_autostart` warns about it.

## Devices

Lists wireless peripherals (mouse, keyboard, gamepad, headset) with their battery and connection,
rendered from `scripts/devices/devices.sh`, the one reader shared with the Waybar battery
module and the low-battery toast. `shell.qml` runs it when the page opens and every 10 s
only while `opened && !closing && category === "devices"` with no search query; nothing
runs otherwise: hiding the page stops a read in flight and discards a late result
(`deviceRead.mjs` `fresh`). `alert` (low/critical) comes from the script, not the page, and draws the
value in the accent colour, bold. An asleep device shows its last reading; a USB input device
with no readable battery (a dongle or a wired keyboard) shows "Connected" and "No battery info".
A USB headset's battery comes from `headsetcontrol` (optional; without it the headset has no
battery row), and a headset switched off behind its dongle shows "Asleep".
`scripts/hyprland/settings-panel.sh devices` opens it.

## Calendar

Signs in to iCloud and chooses what the calendar card and the bar show. The view draws
**Account** first: signed out, the Apple ID and app-specific password fields (the password
reaches `scripts/calendar/setup.sh --sign-in --stdin` on stdin, never argv; `calendar.mjs`);
signed in, the account, the sync line (`status.json`) with **Sync now** (every 15 minutes
and whenever the card opens) and a two-press **Sign out**. **Calendars** follows, one
switch per calendar (read-only ones are labelled), stored in `options/calendar-hidden`.
The catalog sections then add **Events** (`calendar-declined`, show declined invitations)
and **New events** (`calendar-default`, `calendar-alert`, `calendar-duration`, used by the
card's new-event sheet). `shell.qml` reads `calendarStatus` every 5 s only while the page
is shown; a stale read is dropped (`calendar.mjs` `fresh`). A save of `bar-agenda` or any
`calendar-*` option runs `scripts/calendar/sync.sh --render`, and a failed render rolls
the option back. The calendar itself is `docs/internals/calendar.md`.

## Bar

One select row per Waybar module that can come and go: CPU, Memory, GPU and Disk
(Always · Only when high · Hidden), Network (During traffic · Always · Offline only) and
Updates (When pending · Hidden). Calendar (`bar-agenda`: Within 12 hours · Today only ·
Next event · Hidden, default Within 12 hours) sets how far ahead the next-event pill beside
the clock looks (`scripts/waybar/agenda-bar.sh`). Each is a plain `options/bar-*` file; a
missing or unknown value means the first choice, which is also the default, so the bar looks the same
until something is changed. "High" is the amber threshold: 70%, disk 80%.
`scripts/hyprland/settings-panel.sh bar` opens it.

Below them, the bar's layout: Position (Top · Bottom), Style (Floating: today's inset,
rounded, fully bordered bar · Docked: edge to edge, square, one border line facing the
windows), Background opacity (0–100 %), Border, Monitors (All, or one connected output — an
empty `options/bar-output` means all, so the tracked default names no connector), Clock
seconds (bar only; the lock screen keeps its hour/minute layout) and Workspaces (Dots ·
Numbers). Their files are `bar-position`, `bar-style`, `bar-opacity`, `bar-border`,
`bar-output`, `clock-seconds` and `bar-workspaces`.

Whoever renders a module applies its mode:

- **cpu, memory, disk** are Waybar built-ins, reachable only through config. A save runs
  `scripts/waybar/bar-modes.sh`, which renders `~/.local/state/waybar/bar.jsonc` and reloads
  Waybar. The include blanks per-state formats: `format-normal` for "high" (config.jsonc
  gives each a `"normal": 0` state below warning), all three for "hidden". An empty format
  hides the module.
- **gpu.sh, network.sh, updates.sh** read their own option when Waybar (re)starts them,
  which the same reload does. A hidden GPU never calls `nvidia-smi` and hidden updates never
  run `checkupdates`, so hiding a module also stops its polling.

- **Layout** is rendered by the same `bar-modes.sh`: `position`, the four `margin-*` keys
  and `output` go into `bar.jsonc`, and background, border and radius into
  `~/.local/state/waybar/bar.css`, which the tracked symlink `waybar/bar.css` exposes to
  `style.css`'s `@import`. Those keys are gone from `config.jsonc` and `style.css`: the
  main config wins over an include, and a later `style.css` rule over an import.
- **Clock seconds** belong to `clock-format.sh`, which adds `:%S` and `"interval": 1` to
  `clock.jsonc`; `config.jsonc` must set neither `clock.format` nor `clock.interval`.
- **Workspaces** are drawn by the native module `cffi/workspaces` (`waybar/workspaces/`),
  which reads `bar-workspaces` once when it starts, so the `bar-modes.sh` reload is what
  applies a save. Anything but `numbers` keeps the dots: ring, disc, and the accent pill the
  current dot stretches into. Numbers mode draws the workspace number instead, dims empty
  ones since a number has no hollow form, and puts the active one in the same pill with the
  same motion; the module adds a `numbers` class so `style.css` can set its insets.
- **Position and Style reload Hyprland** after saving: `hypr/config/apptype.lua` reads both,
  and `rules.lua` places the picture-in-picture window clear of the bar with them.
- **Monitors** are enumerated from `hyprctl monitors -j` on every read; a saved output that
  is not connected stays listed as "(disconnected)" rather than breaking the row.

The four resources are one `group/resources`. Its outer padding lives on whichever member
is first or last while visible (`#resources > :first-child > *`): padding on the group box
itself left a 10 px gap behind when all four were hidden, measured.

Traps:

- **The main config wins over an include key by key.** `waybar/config.jsonc` must never set
  `format-normal`, `format-warning` or `format-critical` on cpu/memory/disk, or a mode
  silently stops working; `test-bar-modes.sh` fails if it does. The same reason puts the GPU
  mode in its script: an include cannot override the `exec` the main config sets.
- **Unknown values read as the default; a missing file does not.** The backend shows an
  unrecognised `bar-*` value as the row's first choice, matching the renderers. A deleted
  option file disables its row, as it does for every slider and for select and toggle rows
  without a catalog default (the Calendar row has one, so it reads its default), while the
  bar itself falls back to the default; the next overlay sync restores the default from
  `defaults/options/`.
- **Blur is unchanged.** Hyprland's `blur-waybar` rule ignores pixels at 50 % alpha or less,
  so the background is blurred only above 50 % opacity; at the default it is not, exactly as
  before. Swapping the threshold to 0.01 and reloading produced a pixel-identical screenshot
  (layer rules apply when a surface maps), so nothing was tuned on a guess.
- **A missing `bar.css` stops Waybar.** A missing JSON include is tolerated, a missing CSS
  import is a stylesheet error Waybar exits on — the same as a missing palette `colors-waybar.css`. So
  `install.sh` renders it, `waybar.sh` renders both includes before every start (the
  Restart Waybar button and the visibility toggle's start path both go through it), and
  `doctor.sh` reports the dangling `waybar/bar.css` symlink as an ERROR. Login's bare
  `waybar` is left as is so the doctor can still check the daemon is alive.
- **Tests must not read the live options.** The network and updates suites point
  `BAR_OPTIONS` at an empty directory; otherwise a user's own "hidden" breaks them, and the
  pre-commit hook with them.

## Network: security rules

`network.mjs`'s `groupSecurity` groups every BSS sharing an SSID and picks the
security **fail-closed**: any 802.1X-only/WEP BSS wins outright (unsupported
here); otherwise any SAE-capable BSS (a PSK+SAE transition BSS included) beats
plain PSK, which beats OWE, which beats open. A weaker BSS sharing the SSID can
therefore never downgrade what the panel offers to connect to, and `nm.js`'s
`addAndActivate` re-derives this from the *live* access points immediately
before connecting — refusing with "The network changed; try again" if a scan
landed in between and the group's security no longer matches the plan.

A **saved profile activates as saved** regardless of this grouping: its own
key management was the user's trust decision when it was created (including
through *Advanced…*), and NetworkManager autoconnects it the same way. The
grouping only governs new connections.

A lone WPA2/WPA3 **transition-mode** AP (advertising both PSK and SAE)
connects with SAE, the stronger of the two — a device whose Wi-Fi hardware
lacks SAE support must use `nm-connection-editor` to force PSK instead.

Display SSIDs are libnm's UTF-8 rendering of the AP's raw bytes
(`NM.utils_ssid_to_utf8`); two different non-UTF-8 byte sequences that render
to the same escaped string are indistinguishable in the network list. This is
an accepted limitation, not a bug: the panel only ever compares and connects
by display SSID.

## Measurements

Measured September 19, 2026 with Quickshell 0.3.1 / Qt 6.11.2 on the author's machine,
2560×1440 at scale 1. Original baseline before the session-snapshot refinement,
six consecutive fresh process launches (OS caches warm):

| Measurement | Observed |
| --- | --- |
| Launcher timestamp to first frame swap | 221–291 ms |
| Launcher timestamp to initial 14 values ready | 348–418 ms |
| Open Quickshell process PSS, last three runs | 105–107 MiB |
| Panel process after closing | Absent (verified via IPC and `/proc`) |
| The panel it replaced (a resident AGS + GJS process, since removed), PSS | About 137 MiB |

A full backend read of every row (`panel-request.sh` with all ids) took about
70 ms with 56 rows and about 280 ms with 89 on September 28, 2026; most of the
increase is the nine File Types rows forking `xdg-mime`. The frame is drawn
before values arrive, so this delays values, not the panel. With the Sound
rows and the richer display read it measured 286 ms median (279–292 ms,
five runs) against 282 ms before, inside the +10 ms budget. With the panel
closed there is no `pactl subscribe`, no `settings-display-*` unit and no
panel process. On the Sound page, audio playback on an awake sink plus three
notifications caused no live read; each default-device change caused one.
The nine File types rows (Default Apps) fork `xdg-mime` on every full read and
are most of the open cost.

A full read on September 29, 2026 measured **302 ms cold** after 40
seconds idle. Five immediate warm runs were 291, 298, 296, 300 and 291 ms,
for a **296 ms median**. Each run used:

```bash
req=$(jq -c '{op:"read",ids:[.rows[].id],monitors:true}' quickshell/settings-panel/catalog.json)
bash scripts/settings/panel-request.sh "$req"
```

After the Network, Date & Region and Startup pages were added (September 29, 2026), measured
with `live-smoke.sh` and the loop above:

| Measurement | Observed |
| --- | --- |
| Full read, five runs (median) | 292, 293, 299, 301, 307 ms (**299 ms**) against the 278 ms probe baseline; two more sets 295 and 299 ms |
| Full read at `ee1ab1d` (before those pages, same session) | 296, 295, 292, 288, 296 and 301, 298, 288, 291, 293 ms (median about 294 ms), so the three pages add about 5 ms; the +21 ms against the baseline is machine drift, not code |
| Empty read (`ids: []`) median | 44 ms |
| Network read median | 48 ms (+4, budget 30) |
| Startup read median | 69 ms (+25, budget 40) |
| `nmcli monitor` RSS on the Network page | 10.9 MB (about 10.7 MB in a second run), one process |
| Off the Network page / closed | `nmcli monitor`: 0; `pgrep -af 'nmcli monitor\|settings-panel/shell.qml'`: no process |

Live checks, September 29, 2026, with screenshots: the Network
page shows the Wi-Fi list, Wired and VPN with "Open Proton VPN"; the Waybar clock shows
`12:08` in 24 h, `12:08 PM` after `region.clock=12h`, and `options/clock` was set back to
`24h`; the Startup and Date & Region pages render (nothing was toggled or changed).
Hyprlock's 12/24 h check ran on 2026-09-29: with `options/clock` at 24h the lock screen showed 15:56, and at 12h the hour label showed 03 at 15:59. The option was set back to 24h afterwards.

The timestamp starts after the launcher's lock, IPC probe and palette load, so
these are not full keypress-to-display measurements. A frame swap is a render
milestone, not a physical screen latency measurement. PSS apportions shared
pages; these values exclude GPU memory and are not a guarantee of an identical
drop in total system usage. Short-lived GJS reads can add memory while loading.
The saving at idle comes from exiting, not from keeping a Qt runtime hidden.

## Verification

```bash
bash quickshell/settings-panel/test/run-tests.sh
node quickshell/settings-panel/test/displays.mjs
node quickshell/settings-panel/test/monitor-lua.mjs # runs monitor.lua under Lua
bash quickshell/settings-panel/test/live-smoke.sh # opens/closes on the desktop
bash scripts/hyprland/test-wallpaper.sh
/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml quickshell/settings-panel/*.qml
scripts/docs/generate-keybindings.sh --check
./test.sh
./doctor.sh
```

`./test.sh` runs this suite. Tests cover keyboard/search/close,
no writes while building controls, slider release and explicit text saves,
backend validation (XKB, fonts, commands, choices), GTK/Kvantum ini
round-trips, File Types subtype handling and rollback, suspend listener
round-trips, animation preservation, notification rollback, main-monitor
write failure, the shared apply/save/reset transactions, Sound choices and
writes, palette saves (generate, then apply, with rollback), the panel's fallback
colours against `palette.sh`, the Calendar page's sign-in and
read helpers, interaction locking, display staging, the pending banner, and every
Apply/Keep/Revert ordering and failure path against a mocked systemd guard. The desktop smoke
check reads every catalog setting without changing them, captures
`/tmp/settings-panel-live.png`, measures opening, and verifies process exit.
Qt's linter reports four warnings on 2026-10-16 (PanelWindow is not creatable
outside Quickshell, an `actionsMenu` id shadowing a property, and two property
lookups on types it has no metadata for); live loading succeeds.

Only a single physical monitor at scale 1 has been tested; multiple monitors
and fractional scaling have not.

Logs and launch/request locks live in `~/.cache/settings-panel/`. Quickshell's
own session logs can be read with:

```bash
qs -p ~/.config/quickshell/settings-panel/shell.qml log -t 50
qs -p ~/.config/quickshell/settings-panel/shell.qml ipc call settings status
```
