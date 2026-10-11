# WoW / Battle.net on this setup

## Current working baseline (2026-09-12)

Launch **Battle.net from Rofi**: the entry is Lutris's own desktop file
(`~/.local/share/applications/net.lutris.battlenet-3.desktop`, machine-local),
which runs `env LUTRIS_SKIP_INIT=1 lutris lutris:rungameid/3`. Lutris stays the
primary launcher because its cursor behaviour is better than Faugus's here; a
migration to Faugus was started and stopped, and the desktop entry was never
changed.

The current chain is Rofi -> Lutris -> Gamescope (SDL) -> UMU/Proton ->
Battle.net -> WoW. Lutris's game configuration is machine-local:
`~/.local/share/lutris/games/battlenet-standard-1762118986.yml`. It uses the
existing `~/Games/battlenet` prefix and `Proton-GE Latest` runner.

Current Gamescope settings in that Lutris entry:

```yaml
gamescope: true
gamescope_flags: --backend sdl --expose-wayland --force-grab-cursor -r 144 --adaptive-sync
gamescope_game_res: 2560x1440
gamescope_output_res: 2560x1440
gamescope_window_mode: -b
```

Only the backend was changed from `wayland` to `sdl` during troubleshooting.
With it, resizing works and, after one retry with unclickable controls, the
launcher's controls respond; this is the setup to keep. Disabling Gamescope was
considered and never applied. Existing Lutris environment and
runner overrides remain intact; there is no verified reason to copy the
different Faugus overrides into this baseline.

Battle.net now opens centred at **1920x1080** instead of 1280x720 on the
2560x1440 monitor. This is the outer window size; Gamescope's internal game
resolution remains 2560x1440. WoW retains its fullscreen/workspace-5 rules.
When a shared Gamescope window leaves fullscreen, returning to its previous
launcher-sized geometry is expected. This does not by itself indicate that
the fullscreen game was rendering at that smaller resolution.

Live verification after the size change: Battle.net opened floating and
centred at 1920x1080; WoW subsequently appeared with initial title
`World of Warcraft`, fullscreen at 2560x1440 on workspace 5. Hyprland reported
no configuration errors. Camera dragging, Super+workspace switching and
repeated fullscreen/resize cycles have not yet been confirmed through this
launch path, so test them there before calling gameplay fully verified.

Audio: to hear WoW's 7.1 mix positionally on headphones, route it to the
virtual surround device once in `pavucontrol` (see `docs/virtual-surround.md`).

The monitor exposes VRR support, but Hyprland currently has `misc.vrr = 0`
and `general.allow_tearing = false`. Neither `--adaptive-sync` nor the
`immediate` window rule proves VRR/tearing is active. Leave display tuning
separate from these input/window tests.

## Historical Faugus recipe

Hard-won launch tuning that this repo **cannot** track directly. `.gitignore`
is a whitelist, so `faugus-launcher/` is ignored, and rightly so: Faugus
rewrites `games.json` on every session (`playtime` alone churns), and the
directory also holds absolute paths, banners, icons and the BattlEye/EAC blobs. So the recipe lives here as
prose instead. A fresh `./install.sh` restores the Hyprland half automatically
and needs this file to rebuild the rest by hand.

Verified 2026-07-26 against gamescope 3.16.24, faugus-launcher 2.0.2, umu
1.4.1-patch1, GE-Proton11-1, Hyprland 0.56.0.

### The Faugus launch chain

Four hops, which is why the window rules have to match two different clients:

```
Faugus Launcher -> env vars -> gamescope -> Battle.net.exe -> WoW
```

Faugus entry `Battle.net`, prefix `~/Games/battlenet`, runner `Proton-GE Latest`
(`~/.local/share/Steam/compatibilitytools.d/Proton-GE Latest`, GE-Proton11-1
at the July verification). `launch_arguments`, verbatim:

```
WINE_SIMULATE_WRITECOPY=1 PROTON_ENABLE_WAYLAND=0 gamescope -w 2560 -h 1440 -W 2560 -H 1440 -r 144 --backend sdl --expose-wayland --force-grab-cursor --adaptive-sync --
```

Plus `envar.txt`: `DISABLE_GAMESCOPE_WSI=1` (now stored in
`~/.config/faugus-launcher/envar.json`; games are now in
`~/.local/share/faugus-launcher/games.json`).

Why each piece is there:

- **`--force-grab-cursor`** — the one that took the longest to find. Without it,
  click-and-dragging to swing the camera lets the pointer cross out of the game
  viewport, which drops Hyprland focus and stops the camera mid-turn. It ruins
  combat. Paired with `ClipCursor "1"` in-game (see below); both halves are
  needed.
- **`--backend sdl`** — nested backend rather than DRM, so gamescope stays a
  normal Hyprland client instead of taking the display.
- **`--adaptive-sync`** — historical VRR intent; see the current-baseline
  caveat above. This flag alone does not enable Hyprland's monitor VRR.
- **`-w 2560 -h 1440 -W 2560 -H 1440 -r 144`** — matches the measured
  2560x1440, 144 Hz panel. These are machine-local dimensions; the tracked
  `hypr/config/hardware/monitor.lua` is host-neutral. Adjust them for a
  different monitor.
- **`--expose-wayland`** — lets the nested client see the Wayland socket.
- **`PROTON_ENABLE_WAYLAND=0` + `DISABLE_GAMESCOPE_WSI=1`** — keep the game on
  XWayland inside gamescope rather than native Wayland, and stop Proton's
  gamescope WSI layer from fighting the nested compositor.
- **`WINE_SIMULATE_WRITECOPY=1`** — Battle.net launcher stability.
- Faugus's own `gamemode=False` and `mangohud=False`, globally and per-game.
  Deliberate; see "Measured and rejected" below.

Known wart: `games.json` sets `addapp_bat` to
`.../Battle.net/faugus-battlenet.bat`, and that file does not exist. Harmless
leftover, but don't be surprised by it.

## The Hyprland half (tracked)

`hypr/config/software/rules.lua`, under `Game window rules`. Each effect is
applied to two named rule tables by `game_rule()` — one matching
`class (?i)^WowClassic[.]exe$` and one matching `class ^(gamescope)$`, title
`^World of Warcraft( [(]grabbed[)])?$` — because with the gamescope wrapper it is
*gamescope* that is the Hyprland client, not the game. Both Classic clients
report the same `WowClassic.exe`, so one pair covers both.

Matching correction (2026-09-12): executable classes are matched
case-insensitively with literal dots. The Gamescope launcher title matches
`^Battle[.]net.*$`, covering the observed initial `Battle.net Login` as well as
`Battle.net`; Hyprland uses full regex matches, so the old `^(Battle.net)`
missed the login window. The WoW title also accepts Gamescope's optional
` (grabbed)` suffix. Both Battle.net rules also set the outer launcher size to
1920x1080. The WoW rule effects remain unchanged. The Rofi Battle.net entry
starts Lutris, whose Gamescope uses the SDL backend; see the current baseline.

Floating, size, workspace and fullscreen rules apply when a window opens.
Restart Battle.net to test the corrected startup match. If Gamescope reuses
that window and changes its title to WoW, the dynamic game effects can match,
but the startup-only fullscreen/workspace effects will not run again. Handling
that transition requires a separate title-event handler; none is added by this
rule update.

- **`immediate on`** — retained from the historical stutter tuning. It allows
  tearing for the window only when compositor-wide tearing is also enabled;
  the current `general.allow_tearing = false` prevents that.
- **`no_blur`, `no_shadow`, `decorate off`** — stop the compositor spending
  anything on effects behind a fullscreen game.
- **`workspace 5` + `fullscreen on`** — the game gets its own workspace, so
  `$Mod+1..4` still flips to a browser without disturbing it.
- **`idle_inhibit fullscreen`** — added 2026-07-26. Nothing in the
  wine/gamescope chain sends an idle inhibit, so `hypridle` would lock the
  screen at its idle timeout (`hypr/hypridle.conf`) over a fullscreen game
  during a cutscene, flight path or queue. The mode is `fullscreen`, not `always`, so switching to
  a browser workspace restores the normal lock timer immediately.

The rule name is **`idle_inhibit`**, with an underscore. Hyprland 0.56 rejects
`idleinhibit` as `invalid field type`. It validates its mode
(`none|always|focus|fullscreen`) and errors on anything else — unlike the
neighbouring `content` rule, which accepts any string including `bogus`, so
`content game` cannot be assumed to do anything without measuring it.

## Deliberate in-game CVars

`Config.wtf` lives per client under
`~/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/<client>/WTF/`,
where `<client>` is `_classic_era_` or `_anniversary_`. WoW rewrites the whole
file on exit, so **edit it only while the game is closed**, and back it up first.

Most of the file is churn — `CACHE-*`, `engineSurvey*`, `gameTip`, quest counts,
`lastAddonVersion`. Ignore all of it. These are the settings that were chosen:

| CVar | Value | Why |
|---|---|---|
| `ClipCursor` | `1` | In-game half of the camera-drag fix; pairs with `--force-grab-cursor` |
| `GxCompatWorkSubmitOptimizations` | `0` | vkd3d/D3D12 work-submit stutter workaround |
| `GxApi` | `D3D12` | D3D12 via vkd3d-proton rather than D3D11 |
| `hwDetect` | `0` | Stops WoW's auto-detect from overwriting these choices on launch |
| `vsync` | `1` | Retained historical setting; not evidence that monitor VRR is active |
| `GxMaximize` | `1` | Fullscreen behaviour inside the gamescope surface |
| `graphicsQuality` | `6` | Quality preset, with the individual knobs below overriding it |
| `shadowMode` / `shadowTextureSize` / `shadowNumCascades` | `3` / `2048` / `3` | Shadow detail |
| `SSAO` | `3` | Ambient occlusion |
| `reflectionMode` | `0` | Reflections off — costly, little visual gain here |
| `worldBaseMip` | `0` | Full-resolution world textures |
| `maxFPSBk` | `60` | Background FPS cap (`_classic_era_` only) |

`RAID*` and `raidGraphics*` duplicates of these exist and are set to match, so
raid encounters don't silently drop to a different profile.

**Both clients must be kept in sync.** On 2026-07-26 `_classic_era_` was missing
`ClipCursor` and `GxCompatWorkSubmitOptimizations` — the two hardest-won fixes
were only ever applied to `_anniversary_`. Both were added to `_classic_era_`
(backup at `Config.wtf.bak-20260726`). When tuning one client, apply it to the
other.

## Measured and rejected

Recorded so this ground isn't re-covered. All measured on the author's machine
(i7-9700K, RTX 3080 Ti, desktop, no battery) on 2026-07-26.

**`gamemode` — not worth wiring up.** Running `gamemoderun sleep 8` and watching
what actually changed:

| Claimed effect | Reality here |
|---|---|
| CPU governor -> performance | No-op. Governor stays `powersave`; `intel_pstate` is in **active** mode, so gamemode won't touch HWP |
| Power profile / EPP | Already `performance` — `powerprofilesctl` is pinned there and EPP reads `performance` |
| ioprio | Not applied (`none: prio 0` during) |
| NVIDIA PowerMizer | Needs explicit `gpu_device`/coolbits config; the card already clocks up under load |
| renice | Applied: `nice -4` |

So the sole working effect is a scheduler priority boost, and niceness only
matters under CPU contention — with 8 cores and one heavy process there is no
contest to win. `gamemoded` is installed and running (D-Bus activated) but stays
inactive because nothing registers with it. Leave it that way.

**`power-profiles-daemon` toggle — pointless here.** Already pinned
`performance`, and `/sys/class/power_supply` is empty. On a desktop it would buy
thermals and fan noise, not battery life.

**Session-level "gaming mode" — not built, on purpose.** The idea was to hide
waybar, force swaync DND and inhibit idle whenever a game was running. It
dissolved on inspection:

- Waybar is `"layer": "bottom"` (`waybar/config.jsonc`) with an exclusive
  zone, so a fullscreen window already occludes it completely. Hiding it gains
  no screen space during play, and would remove the bar exactly during the
  workspace-switched moments when it's wanted.
- The real workflow is `$Mod+1..4` to a browser workspace and back, not
  alt-tabbing out of a fullscreen window. Anything scoped to "the game is
  *running*" is therefore wrong; it has to be scoped to "the game is
  *focused*". `gamemode`'s `start=`/`end=` hooks are process-lifetime only, so
  gamemode cannot express that distinction at all.
- Notification toasts over the game and mid-game `hyprlock` had never actually
  occurred in practice. The lock risk was closed by one window rule
  (`idle_inhibit fullscreen`) with no script, daemon or state file — and hence
  nothing to restore if the game crashes.

Deliberately **no `doctor.sh` check** for any of this. `games.json` is
git-ignored and machine-local, so a check would be a second source of truth and
would ERROR on any machine without Faugus installed.
