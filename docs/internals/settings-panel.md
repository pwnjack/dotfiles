# Settings panel

`CLAUDE.md` keeps the rules that must hold on every edit; this file has the reasoning and the traps. `docs/settings-panel.md` describes what each page does, how the catalogue and backend sources work, and the measurements; read it first and use this file for what an edit can break.

`quickshell/settings-panel/shell.qml` starts on demand through `scripts/hyprland/settings-panel.sh` (Super+I and Waybar) and exits once pending saves finish. There is no login autostart, and nothing runs while it is closed.
`catalog.json` is the only list of settings, categories and sections; `pages.mjs` validates it and `test/catalog.mjs` freezes the row-id set, because ids are API. The frame appears before values arrive: a short-lived GTK-free GJS helper (`request.js`, serialised by `scripts/settings/panel-request.sh`) reads them outside the UI thread.

## Persistence

- `persist.js` serialises Hyprland apply/save operations into the untracked `${XDG_STATE_HOME:-~/.local/state}/hypr/overrides.lua`, so panel use never dirties the repo. It waits for an `ok` reply before saving, reloads the saved configuration if a write fails, and passes the failure to the panel's status message. Its regression tests exercise that implementation directly.
- Resets remove only the selected override and reload the Lua configuration; there is no second table of default values. A failed reset tries to restore the previous file and reload it. `hyprctl configerrors -j` may report `[""]` when healthy.
- `backend.js` preserves custom hypridle and hyprsunset content and rolls file changes back on reload failure. Night light state still goes through `nightlight.sh`. Writes to overlay-rendered files run `overlay.sh sync` afterwards (`state.md`).

## Colours

Theme colours come from the shared palette loader at launch, including `SETTINGS_ERROR` from `wal_role error` for alerts. The QML fallbacks match the loader's matugen surfaces, text, accent pair and error.

A `theme-scheme`, `theme-contrast` or `theme-prefer` save or reset resolves `${XDG_CACHE_HOME:-~/.cache}/current_wallpaper` first, then runs `scripts/theming/generate-palette.sh <image>` with its default output directory and `scripts/theming/apply-wal.sh`. Only generation failure rolls the option back and regenerates the previous choice. Applying components is best effort: its failure keeps the new option and palette and the save succeeds, and the panel has no way to show a non-fatal message, so it swallows that. This bypasses `wall.sh` on purpose: its transition delay, unbounded lock wait and failure toast belong to wallpaper changes. The generator has its own bounded publication lock and a timeout for each matugen pass.

## Traps

- **Sound page error.** `soundError` is the Sound page's own, not the shared `problem` banner; `SoundView.qml` shows it with a Retry button (`retrySound`) and keeps the list already shown. The next good read clears it. The `audioEvents` parser feeds one 300 ms debounce, so there is no second `pactl subscribe`.
- **Sound name fields.** `SoundView.qml` draws a copy of the `soundDevices` reply that it keeps while a name field has focus, because replacing a Repeater's array rebuilds its delegates and wipes typed text.
