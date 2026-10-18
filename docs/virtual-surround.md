# Virtual surround for headphones

`pipewire/pipewire.conf.d/60-virtual-surround.conf` adds one output device,
**Virtual Surround 7.1 (headphones)** (`effect_input.virtual_surround`). It
accepts 8 channels and renders each one binaurally, as a sound coming from
that speaker's direction, into plain stereo for the headphones. The headset
never receives more than stereo. A Logitech G533, for example, accepts exactly
2 channels (see `/proc/asound/card*/stream0`); the "Digital Surround 5.1
(IEC958/AC3)" profile PipeWire offered for it encodes AC3 for an S/PDIF
receiver, which a USB headset does not have. Its card belongs on **Analog
Stereo Output + Mono Input**.

The rendering is libmysofa's MIT KEMAR head-related transfer function (no
download; libmysofa is a pipewire-audio dependency), at the standard
7.1 speaker angles: fronts 30°, sides 90°, rears 150°. A 5.1 source's two
surround channels land on the sides or the rears depending on which its
layout names, so they sound either beside or behind you. LFE has no
direction and goes equally to both ears. Every channel is mixed at -6 dB so
a dense mix does not clip; raise the volume to compensate.

## How to use it

- **The default output stays the headset itself.** Desktop sounds, music,
  browsers and voice chat go straight to it, unprocessed. Stereo gains
  nothing from virtual surround and sounds coloured through it.
- **Send only surround sources to the virtual device**, one app at a time:
  games that mix 5.1/7.1, and films with a 5.1 track.
- The virtual device sends its output to the current default output, so it
  always plays on whatever headphones are active and names no device.
- If it is chosen as the default anyway, its output still goes to a real
  device (verified: it does not loop back into itself), but every stereo
  sound is then processed too.

### Routing an app

1. Start the app so it is playing.
2. Click the volume icon in Waybar → **Apps** → the app's route label (it reads
   *Default* until routed) → **Virtual Surround 7.1 (headphones)**.
3. WirePlumber remembers that per application, so it takes effect on every
   later launch. Choose **Default (follows Devices)** in the same menu to undo it.

`pavucontrol` still works for this: it is under the popover's ⋯ menu as
**Advanced…**, and its **Playback** tab has the same per-app dropdown.

To pin it at launch instead, set `PULSE_SINK=effect_input.virtual_surround`
in the app's environment: for a Lutris game that is *Configure → System
options → Environment variables*; for mpv, `mpv
--audio-device=pipewire/effect_input.virtual_surround`.

An app only sends surround if it sees a surround device: Wine/Proton games
read the channel count from the device they are routed to, so routing is the
whole configuration. Leave in-game output on the system default.

### Checking the directions

```bash
PULSE_SINK=effect_input.virtual_surround speaker-test -D pulse -c 8 -t wav -l 1
```

A voice names each speaker in turn ("Front Left", "Rear Right", …); each
should come from that direction. Front and back are the weakest cue with any
generic head model. Different SOFA files can be swapped in by editing the
`filename` lines.
