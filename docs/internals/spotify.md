# Spotify (SpotX and Spicetify)

Moved verbatim from `CLAUDE.md` so the agent instructions stay short. `CLAUDE.md` keeps the rules that must hold on every edit; this file has the reasoning and the traps.

`scripts/spotify/launch.sh` is what starts Spotify: `setup.sh` (run by
`install.sh`, skipped without spotify-launcher) points a per-user copy of
`spotify-launcher.desktop` at it. spotify-launcher swaps in a fresh client
directory on every update, so the marker `.spotx-patched` beside its binary is
gone exactly when the patch is (not in `Apps/`, which Spicetify deletes and
rebuilds whole); without it the wrapper runs `spicetify restore`
(only if the client is unpacked), the latest SpotX-Bash (`-f`, free tier), then
`spicetify backup apply`. The marker means "SpotX applied" and is written before
Spicetify runs: Spicetify's apply drops SpotX's stock `xpui.bak`, after which
SpotX refuses the client, so a Spicetify failure gets its own toast instead of a
retry. SpotX exits 0 on a client newer than it supports; the wrapper compares the
logged versions and warns. Failure starts Spotify unpatched with a toast; the running-Spotify
check happens under the lock, and a running client is never patched. SpotX
`pkill`s `[sS]potify` by name, so the wrapper's file name must not contain it.
See `docs/spotify.md`.
