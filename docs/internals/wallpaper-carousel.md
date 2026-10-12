# Wallpaper carousel

Moved verbatim from `CLAUDE.md` so the agent instructions stay short. `CLAUDE.md` keeps the rules that must hold on every edit; this file has the reasoning and the traps.

`quickshell/wallpaper-carousel/shell.qml` is a separate Quickshell application,
opened on demand by `scripts/hyprland/wallpaper-carousel.sh` (Super+Ctrl+W).
The launcher serialises startup and uses config-specific IPC; it exits on close
to consume no idle RAM. No login autostart is configured.
`carousel-state.sh` reads Waypaper's folder settings, awww's current image and
the shared palette loader on every open. Previews are asynchronous, bounded in
resolution, and virtualised; closing destroys the process after any pending
wallpaper application finishes.
The translucent backdrop uses a Hyprland layer blur rule and follows the shared
blur settings in `decor.lua`; the desktop remains live behind it. Wheel handling
covers the whole overlay.

`carousel-apply.sh` passes the path as an argument to Waypaper with
`--monitor All --no-post-command`, verifies awww and the saved selection, then
runs `wall.sh` synchronously exactly once. Its nonblocking submission lock is
separate from `wall.sh`'s theme lock. Waypaper's own random selection and the
SDDM wallpaper watcher are unaffected by it. Waypaper cannot persist percent signs, and the
query/INI boundary cannot represent line breaks; the helper rejects those names
before submission. See `docs/wallpaper-carousel.md` for checks and measurements.
