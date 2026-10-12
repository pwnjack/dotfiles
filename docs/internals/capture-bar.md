# Capture bar, recording and locking

Moved verbatim from `CLAUDE.md` so the agent instructions stay short. `CLAUDE.md` keeps the rules that must hold on every edit; this file has the reasoning and the traps.

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
