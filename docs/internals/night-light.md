# Night light (hyprsunset)

Moved verbatim from `CLAUDE.md` so the agent instructions stay short. `CLAUDE.md` keeps the rules that must hold on every edit; this file has the reasoning and the traps.

`hyprsunset` runs as a daemon from `config/setup/autostart.lua` and owns the schedule in `hypr/hyprsunset.conf`. That file is rendered, not tracked: `defaults/hypr/hyprsunset.conf` supplies the profiles and four `$variables` (times and temperatures) that the panel overrides per machine (see `state.md`). `nightlight.sh` resolves profile temperatures through the variables. `hypr/hypridle.conf` is tracked and never written; the panel's timeouts go to a state file it sources. `scripts/hyprland/nightlight.sh` is the **only** thing that talks to `hyprctl hyprsunset`; the keybind (Super+Shift+D toggle, Super+Ctrl+D follow-schedule), the waybar `custom/nightlight` module (left click toggles, right click follows the schedule) and the panel's Power rows all call the script.

There is deliberately **no state file** — the daemon is the state, so every surface agrees by construction. A manual override is just a temperature write, which the daemon's own profile timer reclaims at the next scheduled boundary; that is what makes overrides self-expiring with no expiry logic to maintain.

Gotchas, all found by probing the binary rather than reading docs:

- **Profile `gamma` is a multiplier, not a percentage.** `gamma = 100` inside a `profile` block is read as `10000%` and the daemon *exits*. It is optional and defaults to 100%, so the profiles simply omit it. Top-level `max-gamma` **is** a percentage.
- **`identity` has no getter.** Bare `hyprctl hyprsunset identity` is a *setter* returning `ok`, and `temperature` keeps reporting its last set value while identity masks it — so identity state is unreadable. `off` therefore writes the neutral temperature instead of using identity, keeping state readable.
- **`--config` is not a working flag** in v0.4.0 despite the string being in the binary; the path is fixed. Changing the schedule means restarting the daemon (there is no reload request), which is what `quickshell/settings-panel/backend.js` does.
- **A crashed daemon leaves a stale socket**, so `pgrep` is not a liveness probe — only an actual request is.
- `reset temperature` re-applies the active profile; that is the `auto` subcommand.
- The waybar module declares `"signal": 8` so the script can `pkill -RTMIN+8 waybar` for an instant icon update instead of waiting out the interval.
- **Notification icons must be non-symbolic.** **swaync 0.12.6 renders nothing at all for Papirus-Dark's symbolic icons** — it reserves the icon slot and leaves it blank. `notify-send -i` must use the **non-symbolic** name (`weather-clear-night`, not `weather-clear-night-symbolic`). Papirus-Dark also ships its symbolic `status/` set with the light theme's `#444444`, so a symbolic icon that a GTK lookup finds can still be invisible on a dark plate; check the resolved SVG's `ColorScheme-Text`, and screenshot the toast.
