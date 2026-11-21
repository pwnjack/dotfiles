# Media card

`quickshell/media/shell.qml` is the on-demand card started by
`scripts/hyprland/media-popover.sh` when Waybar's media module is left-clicked
(cursor-anchored) in the shared bar-card window (see `update-card.md`). IPC
target `media`: `ping`, `toggle`, `close`, `status`. Nothing of it runs while
it is closed. It shows the track the bar shows, with its album art, a seek bar
and previous, play or pause, and next; with two players or more, a row of
chips switches which one the card shows and controls.

## What owns what

| Piece | Owns |
| --- | --- |
| `scripts/hyprland/medialib.sh` | Which player the bar shows, its middle click and scroll act on, and the card opens on. One rule, in its header. |
| `scripts/hyprland/media-popover.sh` | The launch: toggles a running card, exits 0 when no player is on the bus, otherwise passes `media_player`'s answer on as `MEDIA_PLAYER` and signals Waybar, whose text can be five seconds old, to show that answer too. |
| Quickshell's MPRIS service | The players and everything read from them. There is no script and no poll of `playerctl` behind the card. |
| `model.mjs` | Every decision, as pure functions: which player matches `MEDIA_PLAYER`, the texts and times, whether the seek row shows and takes input, which buttons are on, the chips, which art URLs are loaded, where a seek lands. Free of I/O and of the clock. |
| `shell.qml` | The controller: holds the shown player and its position, and is the only thing that calls a player (`togglePlaying`, `next`, `previous`, `position`). |
| `Card.qml` | Drawing only, from `Model.view` and `Model.chips`; it calls the controller, never a player. |

## How it opens

1. Quickshell's player list fills a moment after start, one player at a time.
   The window appears as soon as the list holds the player `MEDIA_PLAYER`
   names, so the card opens at its size on the right track.
2. If that player has not come after 300 ms, the card opens on the first
   playing player, then the first; with none, the process quits.
3. A second click before the window appears quits the process instead.

## Rules

- **`MEDIA_PLAYER` is playerctl's name; a bus name is that name with a
  prefix.** Quickshell's `dbusName` is `org.mpris.MediaPlayer2.<name>`, with
  an instance suffix for some players
  (`org.mpris.MediaPlayer2.firefox.instance_1_2810`). `model.named` matches
  the name whole, or the name followed by a dot.
- **The chips change the card, never the bar.** Nothing is stored: every open
  starts on the bar's player, and the card does not follow the bar while it
  is open.
- **The chips depend on the players alone.** `Model.chips` takes no shown
  player and no position, and each chip finds out for itself whether it is
  the shown one. A list that changed with either would rebuild the chips and
  take the keyboard focus off the one just chosen.
- **The position is read, not announced.** Quickshell works a player's
  `position` out when it is read. The controller reads it once a second while
  the card is open and the shown player is playing, and whenever that player
  signals a seek, a state change or a new track. Closed, nothing reads it.
- **A seek is sent on release.** While the thumb is held the bar and the
  elapsed time follow the pointer; one `position` is written when it is let
  go. A player that ignores it shows its own position again at the next tick.
  A thumb still held when the track changes (`view().track`: the player's
  track id, the title and the length) is dropped, and its release seeks
  nothing.
- **The bar is told at once.** On the shown player's `playbackStateChanged`
  and `postTrackChanged` the controller signals Waybar (`RTMIN+10`), the same
  signal `mediactl.sh` sends, so the bar does not wait for its five-second
  fallback.
- **When the shown player leaves the bus** the card moves to another one;
  when the last one leaves, it closes, and a click during that fade does not
  bring it back: `toggle` reopens a fading card only while a player exists.
- **Art is loaded from `https:` and `file:` URLs only.** Any program on the
  session bus can name a URL; every other scheme shows the placeholder, as do
  a missing URL, a loading image and a failed one. Nothing is written to disk.
- **Track text is plain text.** Title, artist, album and chip labels set
  `Text.PlainText`: a track name is arbitrary text.
- **Keys.** Escape closes; Space plays or pauses wherever the focus is; Left
  and Right seek `model.STEP_SECONDS`; Tab walks the buttons a player allows,
  then the chips; Return presses the focused one.
- **Buttons and chips are named.** A glyph says nothing to a screen reader:
  the three buttons are `Accessible.Button`s called Previous, Play or Pause,
  and Next; the chips are radio buttons named after their player, the shown
  one checked. The seek row is a slider named with the elapsed time, stepped
  by the same five seconds as the arrow keys. The glyphs themselves are
  ignored.
- **Glyphs are code points** (`String.fromCodePoint`), never typed.
- **The size is 1:1** (`uiScale` 1), as for every popover that belongs to the
  bar.
- **Fixtures are invented.** No real track, artist or path from this machine
  belongs in the repository.

## Tests

- `quickshell/media/test/run-tests.sh`: the model under node, and
  `tst_Card.qml` for every state of the view against stand-in players. The
  stand-ins are objects, as the real players are, because a chip knows its
  player by identity.
- `scripts/hyprland/test-media.sh`: the launcher with a fake `playerctl` and
  a fake `qs`.
- No suite loads `shell.qml`. A change to it needs a live open; in a private
  session bus (`dbus-run-session`) a stub MPRIS player can come and go without
  touching the players in use.
