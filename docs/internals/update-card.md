# Update card

Moved verbatim from `CLAUDE.md` so the agent instructions stay short. `CLAUDE.md` keeps the rules that must hold on every edit; this file has the reasoning and the traps.

`quickshell/updates/shell.qml` is the on-demand update card started by
`scripts/hyprland/updates-popover.sh` when the bar's updates module is clicked
(lock, IPC toggle, cursor-anchored, exits on close). Update starts
`scripts/updates/updates-run.sh` under `setsid`: it runs the root helper
`/usr/local/bin/system-update` (installed from `updates/system-update-root.sh`
by `updates/setup-sudo.sh`, one no-argument NOPASSWD rule), then Flatpak, and
`fold.mjs` folds the stream into `$XDG_RUNTIME_DIR/updates/state.json` through
the pure `model.mjs` the card also imports, so card and bar agree. AUR updates
stay in the terminal (`scripts/updates/terminal.sh`). See `docs/updates.md`.
