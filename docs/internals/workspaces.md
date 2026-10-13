# Native workspace module

Moved verbatim from `CLAUDE.md` so the agent instructions stay short. `CLAUDE.md` keeps the rules that must hold on every edit; this file has the reasoning and the traps.

The workspace dots are one native Waybar module, `waybar/workspaces/` (C,
GTK3/cairo, Waybar CFFI ABI 2), drawn on one canvas from one animation clock:
the leaving pill contracts while the arriving dot stretches, both amounts
from the same clock, so the row's width is exactly constant and nothing
beyond them moves by a pixel. The ten CSS-animated custom modules it replaced
could not do that: GTK rounds each animating `min-width` up (a 1 px wobble)
and separate processes landed their updates up to tens of ms apart.
`model.c` (state, parsers), `anim.c` (groups, curves, layout) and `render.c`
are pure and tested headless; `hypr.c` speaks Hyprland's sockets directly and
is tested against fake sockets; it connects and writes each command
synchronously and reads only the reply async, because Hyprland blocks its
main loop from accept() until the request arrives (an async write deadlocked
with Waybar's own synchronous Hyprland calls: a 5 s freeze per window close); `module.c` is the GTK glue and must export all
five `wbcffi_*` functions — Waybar calls `update` and `refresh`
unconditionally. `scripts/waybar/build-workspaces.sh` builds out of tree
(never inside the repo) into `~/.local/lib/waybar/workspaces.so` and renders
`~/.local/state/waybar/workspaces.jsonc` with the absolute `module_path`,
because Waybar `dlopen`s that string verbatim. A content stamp beside the
library (`<lib>.sha256`, a hash of the sources, Makefile and script) decides
whether a rebuild is needed; `--check` compares only and exits 0 current / 1
stale or missing, which is what `doctor.sh` uses. Colours and insets stay in
`style.css` (`#workspaces`, `.active`, `.numbers`); sizes live in `anim.c`.
`scripts/hooks/post-merge` (`post-checkout` is a symlink to it) runs the build
after a pull or branch switch, in the main worktree only, so a pull never
leaves a stale library. `docs/workspaces-native.md` has the build flow and the
way back to the CSS dots: tags `workspaces-css` (before) and
`workspaces-native` (the merge), undone with `git revert -m 1`.

## Keyboard stepping

`hypr/config/software/workspace_step.lua` implements Super+Ctrl+arrow stepping and keeps it bounded to the dot row, as scrolling over the module is.
