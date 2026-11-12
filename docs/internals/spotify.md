# Spotify (SpotX and Spicetify)

`scripts/spotify/launch.sh` is what starts Spotify; `setup.sh` (run by
`install.sh`, skipped without spotify-launcher) points a per-user copy of
`spotify-launcher.desktop` at it. Flow, marker, failure handling, prefs stamp
and traps: [spotify.md](../spotify.md#how-it-works).

- The `.spotx-patched` marker means "SpotX applied" and is written before Spicetify runs, so a Spicetify failure gets its own toast instead of a retry. [How it works](../spotify.md#how-it-works).
- SpotX exits 0 on a client newer than it supports; the wrapper compares the logged versions and warns. [How it works](../spotify.md#how-it-works).
- The running-Spotify check happens under the lock, and a running client is never patched. The lock outlives the wrapper's exec until `pgrep` sees the client (at most 5 s), so a launch queued behind it cannot miss the starting client.
- SpotX `pkill`s `[sS]potify` by name, so the wrapper's file name must not contain it. [Traps](../spotify.md#traps).
