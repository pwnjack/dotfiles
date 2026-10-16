# Native workspace module

The workspace dots on the bar are a compiled Waybar CFFI module,
`waybar/workspaces/` (C, GTK3/cairo). It replaced ten CSS-animated custom
modules whose animation could not be made pixel-exact (GTK rounds each
animating `min-width`, so neighbours wobbled by 1 px). It is the only compiled
component in the repo, and that has a cost — this page is what that cost is
and how to remove it.

## How it gets built

| When | What runs | Result |
|---|---|---|
| Fresh install | `install.sh` installs `gcc make pkgconf gtk3 json-glib`, then runs `scripts/waybar/build-workspaces.sh` | `~/.local/lib/waybar/workspaces.so` and the `~/.local/state/waybar/workspaces.jsonc` include. A failed build is a warning; the install continues. |
| `git pull`, branch switch | `scripts/hooks/post-merge` (`post-checkout` is a symlink to it) re-renders the machine-state overlay, then runs the build script | A hash check when nothing changed; a rebuild when the sources did. Restart Waybar to load it. |
| Anything else | `./doctor.sh` | Reports a missing or stale library and the command that fixes it. |

The hooks are active because `install.sh` sets `core.hooksPath scripts/hooks`.
They build only in the main worktree: the library path is shared, and a linked
worktree must not replace the live bar's library.

A running Waybar keeps the library it loaded. A rebuild takes effect on the
next start (`killall waybar; scripts/waybar/waybar.sh`, or log in again).

## The way back to the CSS dots

Two tags mark the switch:

- `workspaces-css` — `main` just before the native module was merged: the CSS
  dots, with the 1 px wobble, no compiler needed.
- `workspaces-native` — the merge commit that brought the module in.

To drop the module:

```bash
cd ~/.config
git revert -m 1 workspaces-native   # one commit that undoes the whole merge
```

If later commits touched the same files (`waybar/style.css`,
`waybar/config.jsonc`, `install.sh`, `CLAUDE.md` are the likely ones), the
revert stops on conflicts. Resolve each one by keeping the later change and
restoring the CSS-era workspace parts; `git diff workspaces-css
workspaces-native -- <file>` shows exactly what the merge changed in that file.

Then remove what the build left outside the repo and restart the bar:

```bash
rm -f ~/.local/lib/waybar/workspaces.so ~/.local/lib/waybar/workspaces.so.sha256 \
      ~/.local/state/waybar/workspaces.jsonc
killall waybar; ~/.config/scripts/waybar/waybar.sh
```

The revert also removes the git hook (it was part of the merge), the doctor
check and the five build packages from `install.sh`'s list; the packages
themselves stay installed until removed with pacman.

## Things learned the hard way

- **Write Hyprland commands synchronously.** Hyprland blocks its main loop from
  `accept()` until the request bytes arrive. An asynchronous write deadlocked
  with Waybar's own synchronous Hyprland calls and froze the compositor for 5 s
  on every window close — and, on monitor wake, long enough for Hyprland to
  kill hyprlock. `hypr.c` connects and writes in one step, as `hyprctl` does.
- **Request a height as well as a width.** The drawing area is what holds the
  bar at 40 px when the taskbar and title are empty; the height is the slot
  plus `#workspaces`' vertical margins in `style.css`.
- **Test with real input.** Closes dispatched through `hyprctl` never triggered
  the freeze; Super+Q did. Under the Lua config, legacy `hyprctl dispatch exec
  …` is a syntax error that does nothing — use
  `hyprctl dispatch 'hl.dsp.window.close()'` and check that it took effect.
