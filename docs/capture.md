# Capture bar: screenshots and screen recording

Super+Shift+S opens the capture strip on its Screenshot tab, Super+Shift+R on
its Record tab. Super+S (region to disk) and Super+Alt+S (region to swappy)
keep their own target. While a recording runs, a red timer sits at the left of
Waybar's right-hand modules; click it, or press Super+Shift+R, to stop and save.
During a start delay the pill is amber and a click cancels the countdown.

## Pieces

| Piece | Job |
|---|---|
| `quickshell/capture/` | The strip. `model.mjs` is the pure model; `Strip.qml` draws it; `shell.qml` owns the window, IPC and the option files. Exits on close. |
| `scripts/hyprland/capture-bar.sh` | Launcher: lock, IPC toggle, palette, daemonize. `record` while recording stops instead. |
| `scripts/capture/record.sh` | The only driver of gpu-screen-recorder. State in `$XDG_RUNTIME_DIR/capture/recording.json`, recorder log in `gsr.log` beside it. |
| `scripts/hyprland/screenshot.sh` | The only screenshot command (hyprshot): `screen`, `window`, `region`. |
| `scripts/hyprland/lock.sh` | The only lock path (autologin in `startup.sh` runs hyprlock directly; nothing records then); locks first, saves a recording in a detached process. |
| Waybar `custom/recording` | Hidden when idle; `interval: once` plus signal 11; click stops (or cancels a countdown). |

## The strip

IPC target `capture`: `ping`, `toggle <mode>`, `open <mode>`, `close`,
`status`, and `run`, a seam for scripted checks that presses the action button
and acts only while the strip is open. Option writes are synchronous
(`blockWrites`), so the script the strip starts reads exactly what it shows.

The capture is started detached, stdio closed, after Hyprland reports the
`capture-bar` layer closed (400 ms fallback if no event arrives). The layer
rules are blur and `no_anim`, so the strip is gone from the screen before the
shot and never appears in it. Button widths are set so that no label is ever
elided, which the offscreen QML test enforces; Annotate is 60 px wide for that
reason.

## Options

One value per file in `options/`, written by the strip the moment a control
changes. `record.sh` reads `capture-rec-target`, `capture-delay`,
`capture-audio` and `capture-mic`, so the keybind and the strip never record
differently; `screenshot.sh` reads `capture-freeze`. `capture-shot-target` and
`capture-annotate` are read only by the strip, which passes target, annotate
and delay to `screenshot.sh` as argv. The Freeze toggle (`capture-freeze`) applies to every screenshot path,
including Super+S and Super+Alt+S (Super+Alt+S did not freeze before the strip);
they ignore the strip's other options by design. The files:
`capture-shot-target`, `capture-rec-target` (`screen|window|region`),
`capture-delay` (decimal seconds, `0` = off, so `08` is 8 s), `capture-freeze`,
`capture-annotate`, `capture-audio`, `capture-mic` (`true|false`).

They are per-machine state, gitignored rather than tracked, so using the strip
never dirties the repo. A missing or invalid file is the default: region
screenshots, full-screen recordings, and every toggle off. The defaults live
in `model.mjs` (`DEFAULTS`) and in the scripts' fallbacks, and the strip
creates a file the first time its control changes.

## Recording

`gpu-screen-recorder -w <monitor> | -w WxH+X+Y -c mp4 -k h264 -ac aac -f 60
-q very_high -cursor yes [-a <audio>] -v no
-o ~/Videos/Recordings/Recording_YYYY-MM-DD_HH-MM-SS.mp4`. Region and window
recordings use `-w WxH+X+Y` because gpu-screen-recorder 6.1.3 deprecates
`-w region -region`. `<audio>` is `default_output` (desktop audio),
`default_input` (the microphone) or both joined by `|`, mixed into one track.
Capture is KMS through `gsr-kms-server`, which needs `cap_sys_admin` (the
package sets it; `doctor.sh` warns if it is lost). No portal dialog.

- **Window** recording records the window's rectangle at the moment you click
  it. Moving the window afterwards is not followed.
- **Region coordinates** are passed exactly as slurp prints them. Untested on a
  scaled monitor (only scale 1 has been tried).
- **Very small regions fail.** NVENC rejected 64x64 and accepted 256x256;
  a tiny selection ends in a "Recording failed" toast.
- **Identity.** record.sh identifies the recorder by pid and its `/proc` start
  time (`since` in the state), so a recycled pid is never mistaken for it. Stops
  are serialised by a flock. A click that lands on the countdown boundary
  cancels and discards. If the recorder dies mid-recording, a "Recording
  stopped" toast says so and the bar clears; the partial file stays in
  `~/Videos/Recordings` and the toast names it. The same holds for a stop that
  times out and is killed ("Recording not saved", partial file kept). While the file is finalised the
  module reads "saving".
- **Power menu.** Log out, Reboot and Shut down (once confirmed) run
  `record.sh stop` first, bounded to 12 s, so a running recording is saved.
- **Stop** sends SIGINT and waits up to 10 s for the file; the toast offers
  Open and Show in folder. Nothing goes to the clipboard.
- **Saved toasts.** Recordings and screenshots post the same toast
  (`scripts/capture/toast.sh`): Open, and Show in folder, which selects the file
  through D-Bus's `org.freedesktop.FileManager1`. hyprshot runs with `-s`, since
  its own toast has no actions; a cancelled selection writes no file and posts
  nothing. Strata, Nautilus, Dolphin and Thunar all claim that D-Bus name.
  D-Bus picked Nautilus whatever the preference said, so
  `scripts/settings/file-manager.sh` copies the configured file manager's own
  service file into `~/.local/share/dbus-1/services/`, which wins. install.sh
  and the panel's File manager row run it; it covers every app's Show in
  folder, not only ours.
- **Waybar.** The module runs once and on signal 11; record.sh sends it on each
  change and once a second while recording, so an idle bar runs nothing. The
  glyph is in `<span size='large'>`, the module carries its own 15 px edges, red
  pill while recording, amber while counting down.

## Lock and suspend

The lock comes first, the save second. logind's `InhibitDelayMaxSec` is 5 s, so
on suspend nothing may stand in front of hyprlock: `lock.sh` starts hyprlock at
once and hands `record.sh stop` to a detached process (a failed or missing save
never prevents the lock). A clip may therefore end with about a second of the
lock screen.

The guard fails closed: `flock -w 1` serialises callers, and only a running
hyprlock of the same user skips locking (a stale one still counts as locked).
Arguments go on to hyprlock. hypridle's `lock_cmd` is `lock.sh`, and
`before_sleep_cmd` runs `loginctl lock-session`, so suspend saves the recording
too. The idle listener (`$lock_timeout`, 30 minutes by default) runs
`lock.sh --grace 5` directly, so the same save happens, and for five seconds a
key press or a mouse move dismisses that lock without a password. Super+L, the
power menu and before-sleep ask for the password at once. hyprlock times the
grace by wall clock, so a suspend inside the window ends it.
hypridle has `inhibit_sleep = 3` (sleep waits until the session is locked)
because its auto mode keys on the string "hyprlock" in `lock_cmd`, which
lock.sh's path lacks.

## NVIDIA note

On NVIDIA, the gpu-screen-recorder package ships
`/usr/lib/modprobe.d/gsr-nvidia.conf` with
`NVreg_PreserveVideoMemoryAllocations=1`; without it the author's driver ran
with 2. It takes effect at the next boot; check the running value with
`grep PreserveVideoMemoryAllocations /proc/driver/nvidia/params`, which reads
1 once it applies.

## Testing

- `scripts/capture/test-record.sh`: record.sh against fakes in `scripts/capture/fakes/`.
- `scripts/hyprland/test-lock.sh`, `test-screenshot.sh`, `test-capture-bar.sh`.
- `quickshell/capture/test/run-tests.sh`: node model tests and offscreen QML tests.
- Live: `record.sh start region 640x360+100+100`, wait, `record.sh stop`, then
  `ffprobe -v error -show_entries stream=codec_name:format=duration -of compact <file>`.
