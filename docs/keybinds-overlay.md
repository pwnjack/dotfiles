# Keybindings overlay (Super+H)

`scripts/hyprland/keybinds-overlay.sh` toggles a full-screen Quickshell HUD,
`quickshell/keybinds-overlay/shell.qml`, on the focused monitor. It reads
`scripts/keybinds/keybinds-sheet.sh --json` on every open (the same parse that
writes `docs/keybindings.md`), shows every bind at once in 2–4 balanced
columns, and exits on close.

- Read-only: typing filters (every word must match the label or the key text),
  Backspace / Ctrl+Backspace / Ctrl+U edit the filter, and Esc, a click or
  Super+H again closes it.
- The prompt and the grid sit as one block centred on the *unfiltered* grid's
  height, and the grid is top-aligned under the prompt. Filtering therefore
  narrows the results in place: the prompt's line never moves while you type,
  matches appear right under it rather than mid-screen, and a new filter
  starts scrolled to the top. Only the text is centred; the caret and the
  `N of M` count hang off its right edge.
- The wheel scrolls by pixels, and only when the columns overflow the output.
- Colours come from `palette.sh` at launch (the accent is matugen's `primary`
  role); accent text falls back to the foreground when the accent is below 3:1
  on the background (`sheet.mjs`).
- The backdrop blur is the `blur-keybinds-overlay` layer rule in `rules.lua`.
- Every size is a 1080p size times `uiScale`: the output's height, or the
  height a 16:9 output of its width would have if that is smaller, over
  1000, clamped to 1–1.6. The sheet keeps its physical size on a 1440p panel,
  a portrait output is not scaled up into narrow columns, and column width
  and count scale with it.
- Labels are the trailing `--` comments in `keybinds.lua`. How much room a
  label gets depends on its keycaps, so there is no character budget: instead
  `tst_Overlay` renders the real sheet, in the `options/font` keycap font, at
  1366×768, 1920×1080, 2560×1440 and portrait 1080×1920, and fails if any
  label is elided. `test/test-docs.sh` runs that one test on every commit,
  since a label changes in `keybinds.lua`, not here. Shorten the comment
  rather than the type.

## Checks

- `bash quickshell/keybinds-overlay/test/run-tests.sh` (model + offscreen view)
- `bash scripts/keybinds/test-keybinds-sheet.sh` (parser, JSON, key vocabulary)
- `qs -p ~/.config/quickshell/keybinds-overlay/shell.qml ipc call keybinds status`
  while open: `{opened, loading, query, shown, total, columns, error}`
- `console.info` lines (including the ready time) go to the Quickshell log named
  in `~/.cache/keybinds-overlay/session.log`; read it with `qs log <path>`.

## Measurements

2026-10-03, 2560×1440, three cold opens: window shown to grid ready
258 / 261 / 263 ms; the launcher returned after 272 / 224 / 215 ms. The bash
parse is about 200 ms of that. The backdrop and prompt appear first, so the
delay shows as the grid arriving a moment later, not as a late window.
