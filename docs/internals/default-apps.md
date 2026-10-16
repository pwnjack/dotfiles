# Default applications

Moved verbatim from `CLAUDE.md` so the agent instructions stay short. `CLAUDE.md` keeps the rules that must hold on every edit; this file has the reasoning and the traps.

Five mechanisms, one source each. **`mimeapps.list`** (default tracked in `defaults/`, the machine's copy
rendered by the settings overlay and written by the
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
hand-written list alone. **D-Bus `FileManager1`** is `file-manager.sh`'s and
**portal `FileChooser`** is `file-chooser.sh`'s (both below).
`TERM` is never set by config: each terminal sets it.
`check_defaults` warns when a variable in this shell or the systemd manager,
xdg-terminal-exec, or a `mimeapps.list` entry whose desktop file exists names a
program that is not installed; associations for apps this machine never had are
skipped, since lookups fall back past them.

## File manager and file chooser

Strata is the repo's default GUI file manager (`strata-bin` from the AUR).
Thunar stays installed and themed, and remains the second folder association.
`defaults/options/filemanager` selects `strata`, and `defaults/mimeapps.list`
lists `io.github.lgse.Strata.desktop;thunar.desktop;` for `inode/directory`.
Change repo defaults in `defaults/`; the settings overlay renders the live
files. Super+E and “Show in folder” follow `options/filemanager`. Without the
AUR package, pick Thunar in the settings panel.

`scripts/settings/file-manager.sh` makes the configured file manager answer
D-Bus `org.freedesktop.FileManager1`, used by every “Show in folder” action.
It copies the selected program's packaged service into the user data directory,
so another installed file manager cannot win activation by chance.

`scripts/settings/file-chooser.sh` is the source for the portal file chooser.
When `options/filemanager` selects an installed Strata, it registers Strata's
embedded backend in `${XDG_DATA_HOME:-~/.local/share}/xdg-desktop-portal/portals/strata.portal`
and its `--portal` D-Bus service in the same data directory's `dbus-1/services/`.
The executable path is canonical and must contain no whitespace, quotes or
backslashes. Every component of its canonical path must be owned by root or
the current user and must not be writable by group or others. Full paths and
aliases resolving to that binary also select Strata. Selecting another manager
or losing a safe Strata binary removes registrations bearing Strata's service
name and leaves foreign files alone. D-Bus config is
reloaded and the portal frontend is restarted only when a registration changes.
Install and the panel's File manager row run both helpers.

`xdg-desktop-portal/hyprland-portals.conf` prefers `hyprland;gtk` generally and
`strata;gtk` for `org.freedesktop.impl.portal.FileChooser`: Hyprland does not
provide that interface, and a missing Strata backend falls through to GTK.
With `XDG_CURRENT_DESKTOP=Hyprland`, this desktop-specific file takes precedence
over `portals.conf`. Do not use Strata's in-app file chooser or
default-file-manager toggles, or `--install-portal` / `--uninstall-portal`:
they rewrite the tracked `hyprland-portals.conf` and add duplicate per-user
services. The helper dismisses the in-app portal offer whenever a safe Strata
is installed, whatever file manager is selected.
