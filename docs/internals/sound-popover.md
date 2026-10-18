# Sound popover

Moved verbatim from `CLAUDE.md` so the agent instructions stay short. `CLAUDE.md` keeps the rules that must hold on every edit; this file has the reasoning and the traps.

`quickshell/sound/shell.qml` is the on-demand popover started by
`scripts/hyprland/sound-popover.sh` when Waybar's volume icon is clicked (lock,
IPC toggle, cursor-anchored, palette passed in `SOUND_*` variables, exits on
close). Scrolling the icon still runs `wpctl`. IPC target `sound`: `ping`,
`toggle`, `close`, `status`. Nothing of it runs while it is closed: the pins
watch, the battery timer and the microphone meter all live and die with the
process. SwayNC no longer carries a volume widget; the sidebar keeps Do Not
Disturb, media and notifications.

## What owns what

| Piece | Owns |
| --- | --- |
| `model.mjs` | Every decision, as pure functions: labels, which devices show, route targets, the app list, the battery join. Free of I/O, and the Settings panel imports its label and options-file parsers (through `settings-panel/sound.mjs`) so both surfaces name a device the same way. |
| `PipewireAdapter.qml` | Live PipeWire as plain JS objects (`nodes`), the two actual defaults, and the four writes Quickshell can do: default output or input, volume, mute. |
| `shell.qml` | The controller: it joins the adapter, `model.mjs`, the pins watch, the battery reader and the options files, and runs the route requests. |
| `Popover.qml`, `DeviceCard.qml`, `Picker.qml`, `AppRow.qml`, `VolumeSlider.qml` | Drawing only. They read the controller's properties and call its functions. |
| `scripts/sound/sound.sh` | What Quickshell's PipeWire bindings cannot do: move a stream to another output (`route`) and read which streams are pinned (`pins`). |
| Settings panel Sound page | Names and visibility of devices, plus the card's ports and profile. See `settings-panel.md`. |

The QML never decides what to show. A rule changes in `model.mjs` and its
tests (`quickshell/sound/test/model.mjs`, run with the QML cases by
`quickshell/sound/test/run-tests.sh`); `scripts/sound/test-sound.sh` covers the
helper against recorded `pw-metadata` output.

## The controller contract

`Popover.qml` documents it in its header and `tst_Sound.qml` drives it with a
fake controller, so a new property has to appear in both. The properties are
the colours, `monoFont` and `uiScale`; `ready`; `tab` (`devices` or `apps`) and
`picker` (empty, `output` or `input`); `output` and `input` (the current device
or null); `outputs` and `inputs` (`{ shown, hidden }`); `apps`; `targets`;
`status`; `meter`; and `pinsKnown`. The functions are `setTab`, `openPicker`,
`closePicker`, `choose`, `setVolume`, `setMuted`, `route`, `openSettings`,
`openAdvanced` and `close`.

- **`pinsKnown`** is false until the first line of `pins --watch` arrives and
  again once the watch exits. While it is false no route item is checked and
  the status line says routes cannot be read, so the popover never claims
  "Default" for a route it cannot see.
- **`status`** is the route error, else the pins failure, and the Apps tab
  shows it. The route error clears itself after four seconds; the pins failure
  stays until the popover is reopened, because the watch is not restarted.
- A popover on the bar keeps the bar's pixel sizes, so `uiScale` is 1. Only a
  full-screen overlay scales.
- A property must not be named `onAccent`: QML reads an `on<Name>` property as
  the handler of `<name>`'s change signal. The text colour on the accent is
  `accentInk`.

## Tracking rule

The adapter binds every node and every link group (`PwObjectTracker`), because
properties and link states exist only for bound objects, and it rebuilds the
whole `nodes` array once per event-loop turn. A stream's links come from the
global `Pipewire.linkGroups`, not from `PwNodeLinkTracker`: the tracker follows
`isSink`, which Quickshell also sets on **output streams**, so for a playing
app it reports links into the stream (there are none) and never the links out
of it. A live pause and resume check confirmed the global groups follow the
state (the app list went from two to one in 44 ms on pause and back in 39 ms).

`isSink` therefore means "a device sink" only after the adapter has masked it
with `!isStream`; `model.mjs` and its fixture rely on that.

**Playing** means any of the stream's links is `active`. Probed with mpv over
its IPC socket: both channel links go `paused` on pause (the node state goes
`idle`) and `active` again on resume, while `mpv --volume=0` stays `active`, so
silence still counts as playing. The virtual surround leg's links read `paused`
while nothing plays through it, which is why the leg is not listed as an app.

A stream is an app only when its media class is `Stream/Output/Audio` and it
is neither virtual nor passive. Its name is `application.name`, then the node
description, then the node name. Its icon is `application.icon-name` (PipeWire
uses the hyphen), then `application.icon_name`.

## Devices and defaults

- The popover draws and sets the **actual** defaults (`defaultAudioSink` and
  `defaultAudioSource`), the ones playing now. Writes go to the **preferred**
  defaults (`preferredDefaultAudioSink` and `…Source`); WirePlumber then picks
  the actual default, which can differ when the preferred device is absent.
  Never show the preference as if it were what plays.
- Virtual sinks (the surround device) are **route targets only**. They are not
  picker entries and not outputs to choose, unless one is already the default:
  the current default is always shown, hidden or virtual, and carries a
  "Virtual" chip on the output card and its picker row. Virtual sources, such
  as echo cancellation, are ordinary inputs.
- Monitor sources are a PulseAudio view; native PipeWire has no such nodes.
  `classify` still takes only `Audio/Source` nodes, so a monitor could not
  appear as an input.
- Hidden devices (`options/sound-hidden`) and custom names (`options/sound-names`)
  are written by the Settings panel and watched here, so a rename shows at
  once. The current default cannot be hidden.

## Routing, pins and the two ids

A stream has two identifiers and they are not interchangeable:

- the **object id** (`id`) is the PipeWire graph id. It is what Quickshell
  reports and what `pw-metadata` keys its `target.*` entries by, and PipeWire
  **reuses** it: a new stream took id 107 again on every loop of the probe.
- the **serial** (`object.serial`) never repeats. It is the Pulse sink-input
  index, so it is what `pactl move-sink-input` takes, and the value a pin holds
  is usually the target sink's serial.

`sound.sh route <serial> <sink-name>` therefore addresses the stream by serial,
and refuses a serial no current sink input has, so a recycled id cannot move
the wrong stream. `pins` prints `{"<object id>": "<target>"}`, where the target
is a sink serial or, when another tool pinned by name, a `node.name`
(WirePlumber resolves both); `model.mjs` resolves it the same way.

The popover keys everything about a stream by its serial: the app row
(`AppView.key`), a held slider, a mute or volume write and a pending route.
The object id is used only to look up the stream's pin and the live node.
So when a stream ends and a new one takes its id, the newcomer gets a row of
its own, a slider held on the old row commits nothing on release, and a
pending route is never settled by the newcomer's links (`routeReached` finds
the stream by serial first).

- **Default is `-1`.** `route <serial> default` runs
  `move-sink-input … @DEFAULT_SINK@`, which does not remove the pin: it writes
  `target.object -1` and `target.node -1`. A parser treats `-1` as unpinned and
  `pins` never prints it. A stream that ends produces
  `remove: id:<n> all keys`; deleting the one key (`pw-metadata -d <id>
  target.object`) produces `remove: id:<n> key:'target.object'`, which drops
  the pin too. A removal of `target.node` alone changes nothing.
- **Routing to the current default is also `-1`.** Pulse's compatibility layer
  treats the default device as "no pin", so the popover cannot pin an app to
  whichever device happens to be the default. The pin is kept only when it was
  made while another device was the default, and an app meant to stay on the
  headset follows the default after a later change (pavucontrol behaves the
  same).
- The route menu lists Default, the shown real outputs, a hidden device the
  stream is pinned to (so the pin stays visible and checked), then the virtual
  sinks.
- **`pins --watch`** prints `{}` at once, then the whole map after every
  monitor line that changes it, replay included. Consumers take the latest
  line. There is no quiet-period heuristic, because one could drop or delay a
  map. Cost: for a few milliseconds the map is empty before the replay lands,
  so a pinned app can show "Default" for a frame. A failure prints
  `{"ok":false,…}` and exits, which sets `pinsKnown` false. The order of
  `target.node` and `target.object` differs between the monitor and a plain
  dump, so do not rely on it.
- **A route is pending until the stream arrives.** `pactl` exiting 0 means only
  that PipeWire took the request. The row shows the requested target, in
  italics, until the stream links into it, for at most two seconds, then the
  request is retired; a failure sets the status line. A newer request for the
  same app replaces the older. A stream keeps its row while its route is
  pending, even with no active link (it relinks for about half a second), so a
  stream that stops during the window lingers up to two seconds.

## The battery join

The headset's charge comes from `scripts/devices/devices.sh` (the same reader
the Devices page and the low-battery toast use), which now prints the USB id of
a headset as `usb`. `batteryFor` joins it to a sink through the sink's
`alsa.components`, which reads `USB046d:0a66`: the row's `046d:0a66` must
appear in it. Confirmed on a Logitech G533, whose sysfs `idVendor` and
`idProduct` match.

- Only sinks are looked at. The headset's **source** carries the same
  `alsa.components`, so matching sources would attach the charge to the
  microphone too.
- The match must be unique on both sides: two headsets with one id, or two
  sinks with one id, produce no entry rather than a wrong one.
- The reader runs on open and every 60 seconds while open. A failure leaves no
  batteries.

## Traps

- **Properties are strings.** PipeWire's `node.virtual` and `node.passive`
  arrive as `"true"`; the adapter converts them, and `model.mjs` compares
  booleans.
- **Qt's V4 engine** runs `model.mjs`. It has no object spread, `matchAll`,
  `trimEnd`, `Object.hasOwn`, `Array.at` or `TextEncoder`; the file's header
  lists them and the node tests do not catch a miss.
- **A node named `__proto__`** passes the name pattern but cannot be a key of
  a plain object. `parseNames` skips it and `setName` in the panel refuses it
  with "Invalid device name".
- **Replacing a model's array wipes the delegates.** The popover keys its rows
  (`syncKeys`) and updates them in place; the controller replaces its arrays on
  every change, which would otherwise reset a slider mid-drag and a hover.
- **Window mapping.** `opened` is set before `closing` on a reopen, and
  `closing` before `opened` on close; the layer's `visible` binding re-evaluates
  after each assignment, and a moment with both false unmaps the layer and
  blinks. Do not reorder them.
- **Launcher children.** `setsid -f` with stdio closed: a child left on this
  process's pipes dies of SIGPIPE once the popover has exited. Opening Settings
  or Advanced… closes the popover.
- **The mic meter** is a `PwNodePeakMonitor` on the default source and runs
  only while the Devices tab is on screen with no picker open.
- **The layer rule.** `rules.lua` gives the `sound-popover` layer a blur like
  every sibling popover; without it the card renders flat.
- **Light palettes.** Secondary text is the foreground at 75 per cent; dimmer
  fails 4.5:1 on a light palette.

## Other surfaces

- The Sound page keeps what the popover does not do: the card's port and
  profile for the current output, the input port, device names and visibility.
- **Advanced…** in the popover's ⋯ menu opens `pavucontrol` for everything
  else. Routing an app is done from the popover's Apps tab; see
  `virtual-surround.md` and `gaming-wow.md`.
- The tracked SwayNC config has no volume widget, and its stylesheet has no
  `widget-volume` rules.
