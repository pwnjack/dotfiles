# Native workspace module

The workspace dots are one native Waybar module, `waybar/workspaces/` (C,
GTK3/cairo, Waybar CFFI ABI 2), drawn on one canvas from one animation clock
(why, build flow, rollback to the CSS dots and traps:
[workspaces-native.md](../workspaces-native.md)).

- `model.c` (state, parsers), `anim.c` (groups, curves, layout) and `render.c` are pure and tested headless; `hypr.c` speaks Hyprland's sockets directly and is tested against fake sockets, connecting and writing each command synchronously and reading only the reply async ([Things learned the hard way](../workspaces-native.md#things-learned-the-hard-way)); `module.c` is the GTK glue and must export all five `wbcffi_*` functions, because Waybar calls `update` and `refresh` unconditionally.
- `scripts/waybar/build-workspaces.sh` builds out of tree (never inside the repo) into `~/.local/lib/waybar/workspaces.so` and renders `~/.local/state/waybar/workspaces.jsonc` with the absolute `module_path`, because Waybar `dlopen`s that string verbatim. A content stamp beside the library (`<lib>.sha256`, a hash of the sources, Makefile and script) decides whether a rebuild is needed; `--check` compares only and exits 0 current / 1 stale or missing, which is what `doctor.sh` uses. [How it gets built](../workspaces-native.md#how-it-gets-built).
- Colours and insets stay in `style.css` (`#workspaces`, `.active`, `.numbers`); sizes live in `anim.c`.
- `scripts/hooks/post-merge` (`post-checkout` links to it) runs the build in the main worktree only, so a pull never leaves a stale library. The way back to the CSS dots (tags `workspaces-css` and `workspaces-native`, `git revert -m 1`): [The way back](../workspaces-native.md#the-way-back-to-the-css-dots).

## Workspace addresses

Since Hyprland 0.57 a workspace is identified by its address: a numbered one
by its number (its JSON object also carries an integer `id`), a named or
special one by a name that is never a number, with no `id` at all. `model.c`
gives an address that is not a whole number no slot, in `j/workspaces`,
`j/activeworkspace` and the `workspacev2` / `focusedmonv2` events alike. A
`workspacev2` payload with more than one comma cannot be split reliably (either
half may hold one), so it asks for a snapshot instead. An
object with neither an `id` nor an `address` is malformed and still rejects
the reply: the module keeps its last state, so a reply rejected for a
legitimate shape leaves stale dots.

## Keyboard stepping

`hypr/config/software/workspace_step.lua` implements Super+Ctrl+arrow stepping and keeps it bounded to the dot row, as scrolling over the module is.
