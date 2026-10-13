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

Spicetify reads its backup version from `app.last-launched-version` in
Spotify's prefs, rather than asking the client. After an update patched before
its first launch, prefs still names the previous version, so later colour
refreshes would reject the backup as mismatched. Immediately before
`spicetify backup apply`, the wrapper stamps the existing prefs key with the
installed version from `${XDG_DATA_HOME:-~/.local/share}/spotify-launcher/state.json`,
without the package epoch. It reads `prefs_path` from Spicetify's config and
replaces the file atomically while holding the patch lock, with Spotify stopped.
Missing state, an invalid version, or missing prefs or version key is silently
left alone; it never creates prefs or adds the key.
