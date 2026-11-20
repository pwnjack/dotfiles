# Wallpaper carousel

Wallpapers flow through Waypaper, awww and matugen, exactly as they do without
the carousel.

## Controls

| Input | Action |
| --- | --- |
| Super+Ctrl+W | Open or close on the focused monitor |
| Left / Right, mouse wheel anywhere on the overlay, bottom arrow buttons | Browse |
| Click another card | Select it without applying |
| Enter, click selected card, Apply wallpaper | Apply to all monitors |
| Ctrl+F or Search | Search filenames |
| Enter / Down inside search | Return keyboard focus to the cards |
| Escape or Close | Close; browsing alone never changes the wallpaper |
| Super+Shift+W | Existing random wallpaper action |

Escape also works with no search results or an empty folder. Once an application
has been submitted, closing the overlay releases focus while the operation
finishes. The button stays disabled during submission and unreadable previews
cannot be confirmed. Application/theme failures use the existing desktop
notifications and a visible retry message; there is no premature success toast.

The backdrop uses native Hyprland blur with a 24% palette tint, keeping the
desktop live and visible behind the cards. Shared blur settings in `decor.lua`
use size 4 and 2 passes; this lighter blur also applies to other blurred panels.
Images keep their natural proportions inside the skewed card edges.

Run `waypaper` for the original picker and folder preferences. If Quickshell is
missing, the shortcut falls back to Waypaper. `install.sh` declares `quickshell`;
its package supplies the required Qt runtime dependencies. No DMS or Noctalia is
needed. The implementation is independent: the visual reference was
[motor-dev/wallpaperCarousel](https://github.com/motor-dev/wallpaperCarousel),
but no upstream code was copied because reuse permission was not established.

## Integration

- `scripts/hyprland/wallpaper-carousel.sh` locks startup/toggle requests and
  addresses only this configuration's Quickshell IPC. Quickshell's
  `--no-duplicate` is an additional safeguard. The process starts on demand and
  exits when the carousel closes, so it consumes no RAM between uses. No login
  autostart is configured.
- `scripts/hyprland/carousel-state.sh` reads `waypaper/config.ini` on every open,
  including folders, recursion, hidden files, GIF filtering, and name/date sort.
  It queries awww for the visible image, falling back to Waypaper's saved choice.
  It respects the live `animations:enabled` setting, including Hyprland's
  boolean JSON field. The palette reaches QML at launch through
  `qs_theme CAROUSEL`, as for the other on-demand surfaces.
- QML calls `carousel-apply.sh` with an argument array. The helper checks the file
  and holds a separate nonblocking submission lock. It runs
  `waypaper --backend awww --monitor All --no-post-command --wallpaper PATH`,
  verifies the image on every reported output and its saved choice in Waypaper,
  then runs the existing `wall.sh` synchronously once. Waypaper retains its
  transition/fill settings and saved selection for login restoration.
- `wall.sh`, the theme fan-out, random selection, and the SDDM watcher
  keep their existing implementations. The carousel's lock protects its
  submissions only. An external random/Waypaper action can supersede one;
  `wall.sh` continues to read the latest awww state after taking its theme lock.
- Image delegates exist only around the viewport, with one card-width of extra
  buffer. Decoding is asynchronous and limited to at most 1280×1440 requested
  pixels, adjusted for display scale. Qt's shared image cache is disabled for
  these previews. Closing exits the process and releases its Qt/GPU allocations.

Logs and locks live under `${XDG_CACHE_HOME:-~/.cache}/wallpaper-carousel/`.
Quickshell also maintains its own runtime logs and normal Qt caches. No previews
or selections are written to tracked files. Waypaper's existing config symlink
continues to point into the cache.

```bash
# Open or toggle closed / inspect / close this instance
scripts/hyprland/wallpaper-carousel.sh
qs -p ~/.config/quickshell/wallpaper-carousel/shell.qml ipc call carousel status
qs -p ~/.config/quickshell/wallpaper-carousel/shell.qml ipc call carousel close
qs -p ~/.config/quickshell/wallpaper-carousel/shell.qml log -t 50
```

## Verification

Warm opens were barely faster than cold ones, which was not worth holding a few
hundred MiB while idle, so closing exits the process and leaves no carousel RSS.
Synthetic `wtype` modifier injection does not trigger the global Super+Ctrl+W
shortcut, so that check needs a real keypress. `./test.sh` runs both carousel
suites, `scripts/hyprland/test-carousel.sh` and
`quickshell/wallpaper-carousel/test/run-tests.sh`.

## Limits

- Multi-monitor focus placement and fractional display scaling were not tested
  on physical hardware; only one monitor at scale 1 was available. Apply-to-all
  arguments and two-output verification are covered by fixtures.
- Waypaper's ConfigParser cannot save literal `%` in paths. The helper rejects
  those names and line breaks before submission, with a rename instruction for
  percent signs. Spaces, quotes, Unicode, and shell metacharacters stay arguments.
- Separate Waypaper `use_xdg_state` files are not supported by this integration;
  the UI reports that setting and directs you to Waypaper. The repository uses
  the default cache-backed config instead.
- Image formats depend on installed Qt decoders; unsupported/corrupt files show
  an unavailable preview. GIF previews display a still frame.
- A failed backend can still leave Waypaper's saved choice changed, because
  Waypaper saves independently of backend success. The helper detects failure
  and does not run the theme hook; select a working image to repair the choice.
