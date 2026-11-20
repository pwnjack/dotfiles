# Spotify (SpotX and Spicetify)

`scripts/spotify/launch.sh` is what starts Spotify; `setup.sh` (run by
`install.sh`, skipped without spotify-launcher) points a per-user copy of
`spotify-launcher.desktop` at it. Flow, marker, failure handling, prefs stamp
and traps: [spotify.md](../spotify.md#how-it-works).

- The running-Spotify check happens under the lock, and a running client is never patched. The lock outlives the wrapper's exec until `pgrep` sees the client (at most 5 s), so a launch queued behind it cannot miss the starting client.
