# Default applications

Moved verbatim from `CLAUDE.md` so the agent instructions stay short. `CLAUDE.md` keeps the rules that must hold on every edit; this file has the reasoning and the traps.

Four mechanisms, one source each. **`mimeapps.list`** (default tracked in `defaults/`, the machine's copy
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
hand-written list alone. **D-Bus `FileManager1`** is `file-manager.sh`'s (see
Capture bar). `TERM` is never set by config: each terminal sets it.
`check_defaults` warns when a variable in this shell or the systemd manager,
xdg-terminal-exec, or a `mimeapps.list` entry whose desktop file exists names a
program that is not installed; associations for apps this machine never had are
skipped, since lookups fall back past them.
