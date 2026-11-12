# Update card

Contract (behaviour, privilege model, run flow, traps: [updates.md](../updates.md)):

- `quickshell/updates/shell.qml` is the card, started by `scripts/hyprland/updates-popover.sh` (lock, IPC toggle, cursor-anchored, exits on close). Update starts `scripts/updates/updates-run.sh` under `setsid`; `fold.mjs` folds its stream into `state.json` through the pure `model.mjs` the card also imports, so card and bar agree. [How a run flows](../updates.md#how-a-run-flows).
- The root helper `/usr/local/bin/system-update` is installed from `updates/system-update-root.sh` by `updates/setup-sudo.sh`, with one no-argument NOPASSWD rule. [Setting it up](../updates.md#setting-it-up), [Privilege model](../updates.md#privilege-model).
- AUR updates stay in the terminal (`scripts/updates/terminal.sh`). [What it does](../updates.md#what-it-does).
- The planner saves each plan as `plan.json`; the card opens on it through `updates-plan.sh --cached` and checks again only when it is ten minutes old (`model.PLAN_FRESH_SECONDS`). [What it does](../updates.md#what-it-does).
- The bar refreshes after any pacman transaction through `updates/waybar-updates.hook`, which setup installs: a hook rather than a watcher process, so nothing runs between updates. [What it does](../updates.md#what-it-does).
