# Keybindings overlay

`quickshell/keybinds-overlay/shell.qml` is an on-demand, read-only Quickshell
HUD started by `scripts/hyprland/keybinds-overlay.sh` (lock, IPC toggle,
daemonize; exits on close). It reads `scripts/keybinds/keybinds-sheet.sh --json`
on every open. Typing filters in place under a prompt whose line never moves, the
wheel scrolls by pixels only on overflow, and Esc or a click closes it.
`sheet.mjs` is the pure model (filter, highlight, contrast fallback, column
balancing), tested by node; the view is tested offscreen by qmltestrunner. See
`docs/keybinds-overlay.md`.
