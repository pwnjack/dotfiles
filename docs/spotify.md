# Spotify: SpotX ad-blocking and the wallpaper theme

[SpotX-Bash](https://github.com/SpotX-Official/SpotX-Bash) patches the Spotify
client so the free tier plays without ads: audio ads are never fetched, and
banner, video and upgrade prompts are hidden. It changes nothing Spotify
checks on its servers (no offline downloads, no higher bitrate). Patching the
client is against Spotify's terms of service; use it at your own risk.

Each patch downloads the current `spotx.sh` from SpotX-Official's `main`
branch and runs it as you, unpinned, so it keeps up with new Spotify builds.
That trusts whatever upstream publishes at that moment. It needs no sudo: the
client directory is yours.

The client comes from `spotify-launcher`, which installs it under
`~/.local/share/spotify-launcher/install/usr/share/spotify` and replaces that
directory whole on every update (it unpacks into a new directory and swaps it
in). A one-off SpotX run therefore lasts until the next update, and then ads
come back with no sign that anything changed. `scripts/spotify/launch.sh`
closes that gap.

## How it works

`scripts/spotify/setup.sh` (run by `install.sh`; skipped without
spotify-launcher) writes `~/.local/share/applications/spotify-launcher.desktop`,
a copy of the system entry with `Exec` pointed at the wrapper. The same file
name is what makes it replace the system entry in Rofi and as the
`spotify:` link handler.

On every start the wrapper:

1. Takes a lock, so a second launch waits for the first, then hands the call
   straight to Spotify if it is already running (or a `spotify-launcher` is
   about to start it). A running client is never updated or patched. The
   check comes after the lock on purpose: before it, a sibling's update would
   look like a running client.
2. Runs `spotify-launcher --no-exec`, which updates on spotify-launcher's own
   daily schedule and starts nothing.
3. Looks for `.spotx-patched` beside the client binary. An update replaces
   the directory, so the marker disappears exactly when the patch does. It is
   not in `Apps/`, because Spicetify's restore and apply delete and rebuild
   that folder whole.
4. Without the marker, patches under a lock, with a toast while it works:
   - downloads the latest `spotx.sh` first, so a run that cannot get it
     (offline) leaves the client, theme included, untouched;
   - `spicetify restore` if Spicetify has unpacked the client (no
     `Apps/xpui.spa`), because SpotX only patches the packed file;
   - runs `spotx.sh` with
     `--noninteractive --nocolor -f -P <client>` (free tier; `-f` makes a rerun after a
     partial failure start from SpotX's own backup of the stock files); if it
     fails after the restore, `spicetify apply` puts the theme back as it was;
   - `spicetify backup apply`, which backs up the patched client (discarding
     its backup of the previous version) and applies the theme on top.

   The marker means "SpotX applied" and is written as soon as SpotX succeeds,
   before Spicetify runs. Rebuilding `Apps/` drops SpotX's stock `xpui.bak`,
   so after Spicetify the client cannot be patched again: Spicetify's backup
   is the patched copy, and SpotX refuses it ("Detected SpotX-Bash but no
   backup file"). So a Spicetify failure is not retried: its toast names the
   fix, `spicetify backup apply`.
5. Starts Spotify with `spotify-launcher --skip-update`.

Spicetify steps run only when `spicetify` is installed **and**
`~/.config/spicetify/config-xpui.ini` exists.

Patching never stops Spotify from starting. If SpotX does not apply (offline,
upstream unreachable) Spotify starts unpatched, a critical toast says so, and
the next start retries. If it keeps failing, the client is probably in a state
SpotX refuses (patched by SpotX before Spicetify, before this wrapper
existed): close Spotify and run `spotify-launcher --force-update --no-exec`
for a stock client, which the toast also says. A client **newer** than SpotX
supports is different: SpotX exits 0 having applied whatever patterns still
match, so the client is marked patched, and a toast warns that some ads may
show. (The wrapper compares the versions SpotX logs; an unknown one, logged as
`N/A`, falls back to the version SpotX read from `xpui.js`, and never warns on
its own.) Once SpotX catches up, close Spotify and run `spotify-launcher
--force-update --no-exec`; the next start patches the fresh client. The latest
attempt is logged to `~/.local/state/spotify/patch.log`, the update check to
`update.log` beside it.

## Traps

- **SpotX runs `pkill -9 '[sS]potify'`**, which matches process names. The
  wrapper is called `launch.sh` for that reason; a name containing "spotify"
  would be killed mid-patch.
- **SpotX needs `zip`, `unzip` and `perl`** (`install.sh` lists the first two;
  perl is in Arch's base).
- That same `pkill` kills **any** of your processes whose name contains
  "spotify" while a patch runs: other players (spotifyd, spotify_player,
  spotify-qt) or a `spotify-launcher` started by hand mid-update.
- **Never apply Spicetify before SpotX.** SpotX refuses an unpacked client.
  The wrapper restores Spicetify only when the client is unpacked, which an
  update never leaves it (updates install a stock, packed client), so the
  restore always uses a backup of the same client version.
- Starting `spotify-launcher` directly (from a terminal) bypasses the wrapper.
  If it updates, the next start through the wrapper patches again.
- **Do not delete the marker to force a re-patch** on a Spicetify-themed
  client (see above); force an update instead, with Spotify closed.

## Checks

With Spotify closed (`--force-update` on a running client updates it under
its feet):

```bash
bash scripts/spotify/test-spotify.sh          # stubbed: order, failures, lock
spotify-launcher --force-update --no-exec      # simulate an update...
ls -A ~/.local/share/spotify-launcher/install/usr/share/spotify   # ...no .spotx-patched
scripts/spotify/launch.sh                      # patches, then starts
cat ~/.local/state/spotify/patch.log
```

To undo: `rm ~/.local/share/applications/spotify-launcher.desktop`, then
`spotify-launcher --force-update` for a stock client (and
`spicetify backup apply` to keep the theme).

## Theme

Spicetify draws Spotify with the tracked **Pywal** theme
(`spicetify/Themes/Pywal/`), coloured from the wallpaper like the rest of the
desktop. `scripts/spotify/spicetify-theme.sh` selects it, with the
`pywal-live.js` extension, in Spicetify's own config; the first time, run
`spicetify apply` and restart Spotify once.

On every wallpaper change `spicetify/apply_wal_colors.sh` renders the colour
scheme and runs `spicetify -n refresh`, and the extension swaps the new colours
into the open window within a few seconds. The refresh never runs alongside
this wrapper's patch run: it takes the same lock, and when a patch holds it, a
detached waiter refreshes as soon as the patch is done (the patch may already
have applied the previous colours).

The theme keeps Spotify's stock layout on purpose. Rules aimed at Spotify's
generated class names stop matching when a release renames them, silently,
so the theme stays a few rules on top of the stock layout and colours the rest
through Spicetify's colour scheme.

