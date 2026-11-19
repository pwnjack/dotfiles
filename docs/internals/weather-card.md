# Weather card

`quickshell/weather/shell.qml` is the on-demand card started by
`scripts/hyprland/weather-popover.sh` when Waybar's weather is clicked (lock,
IPC toggle, cursor-anchored, palette passed in `WEATHER_*` variables, exits on
close). IPC target `weather`: `ping`, `toggle`, `close`, `status`. Nothing of
it runs while it is closed. It shows the weather now, the next 21 hours in
eight 3-hour steps and up to seven days, each with a low-to-high bar on one
shared scale. There is nothing to press in it: Escape or a click outside
closes it, and opening it again is the retry.

## What owns what

| Piece | Owns |
| --- | --- |
| `waybar-weather` (the bar's service) | The bar's reading and tooltip, and where the machine is. Unchanged by the card. |
| `waybar/weather.toml` | The service's tooltip template: its 0.3.1 default plus a last line `@<latitude>,<longitude>`, rounded to two decimals. `text` is not set, so the bar's text is the service's default. |
| `waybar/waybar-weather-wrapper.sh` | Moves that last line out of the tooltip into the reading's `location` key, and keeps the reading in `~/.cache/waybar-weather.json`. Waybar ignores the key. |
| `scripts/weather/forecast.sh` | The only thing that talks to Open-Meteo for the card: one request for the `location` in the bar's cache, saved as `~/.cache/weather-popover/forecast.json` with `location`, `place` (the first line of the bar's tooltip) and `fetchedAt` added. |
| `model.mjs` | Every decision, as pure functions: which hours and days a forecast still has, the shared scale, labels, condition names and glyphs, the footer note. Free of I/O and of the clock. |
| `shell.qml` | The controller: runs `forecast.sh --cached`, then `forecast.sh` when the copy is not fresh, and holds `forecast`, `phase` and `reason`. |
| `Card.qml`, `HourStrip.qml`, `DayRow.qml` | Drawing only, from `Model.view`. |

## How it opens

1. `forecast.sh --cached` prints the saved copy when it is for the bar's
   current location and in the bar's unit. The window appears once that has
   answered, so the card opens at its size. A second click before then quits
   the process instead of opening it.
2. A copy younger than `model.FRESH_SECONDS` (15 minutes, the service's own
   refresh interval) is the whole answer: no request is made.
3. Otherwise the copy stays on screen with `Updating…` while `forecast.sh`
   fetches. Success replaces it. Failure keeps it, with an amber
   `Offline · updated <age>`; with no copy to keep, the card says
   `No forecast` and the script's reason line.

`forecast.sh` exits 0 with JSON on stdout, or non-zero with one reason line on
stderr, and then leaves the saved copy alone. The card shows that line as it
is: `The bar has no location yet.`, `No connection to Open-Meteo.` or
`Open-Meteo sent no forecast.`

## Rules

- **The location is the bar's.** The card never looks one up. A wrong place
  is fixed where the bar's is: the service's own `cityname` or `geolocation`
  file in `~/.config/waybar-weather/`.
- **`location` is checked before it goes into the URL** (`forecast.sh`). The
  cache is a file any of the user's processes can write, so it must hold
  exactly one JSON object and a coordinate pair of the expected shape.
- **The bar's cache is read once per run.** Coordinates, place name and unit
  come from the same reading, so a forecast is never saved under another
  place's name.
- **A forecast must be whole.** `forecast.sh` refuses an answer, and
  `--cached` a saved copy, that lacks any series the model indexes or has one
  shorter than its times. A partial answer therefore never replaces a good
  copy. Saving itself is best effort: a cache that cannot be written does not
  withhold a forecast already in hand.
- **A user's own service config is left in charge.** The wrapper passes
  `-config waybar/weather.toml` only when `~/.config/waybar-weather/` holds no
  `config.*`; the service reads one or the other, never both. With their own
  config, the card has a location only if their tooltip template ends with the
  coordinate line from `weather.toml`.
- **Times are the place's.** The request asks for `timeformat=unixtime`, and
  the model reads hours and days with the answer's `utc_offset_seconds`, not
  this machine's zone.
- **An aged copy is re-read, not replayed.** Hours before the current one and
  days before today are dropped, so a copy from yesterday still starts at
  `Today`. "Now" is the reading taken with the forecast while it is under an
  hour old, and the forecast's own value for the hour after that. A copy with
  no day left counts as no forecast.
- **The card's "now" is its own fetch**, not the bar's reading, so the two can
  differ by a few tenths of a degree. The header and the first slot show the
  same condition.
- **The unit follows the bar.** `forecast.sh` asks for Fahrenheit only when
  the bar's cached text contains `°F`, and a saved copy in the other unit is
  not shown.
- **Under the title the city alone is shown** (the part of `place` before the
  first comma). A long name is cut; how it feels never is.
- **Hour labels and sun times follow `options/clock`**; weekday names follow
  the session locale, as the calendar card's do.
- **Glyphs are written as `\u{…}` escapes** in `model.mjs`, never typed.
- **The size is 1:1** (`uiScale` 1), as for every popover that belongs to the
  bar.
- **Fixtures use Berlin.** Nothing from `~/.cache` belongs in the repository.

## The tooltip template is a copy

`waybar/weather.toml` repeats the service's default tooltip so that one line
can be added to it. A newer `waybar-weather` that changes its default will not
change the bar's tooltip until the copy is updated; the default is the
template string in the binary (`strings /usr/bin/waybar-weather`).

## Tests

- `quickshell/weather/test/run-tests.sh`: the model under node against a saved
  Open-Meteo answer, and `tst_Card.qml` for every state of the view.
- `scripts/weather/test-forecast.sh`: `forecast.sh` with a stub `curl`.
- `scripts/waybar/test-weather-wrapper.sh`: the wrapper with a stub service.
