#!/bin/bash
# defaults/hypr/hyprsunset.conf rendered with overrides, read by hyprsunset
# itself in a sandbox: no compositor (WAYLAND_DISPLAY=nope), so it parses,
# reports the profile it would apply, and exits.
set -euo pipefail
root="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
source "$root/scripts/lib/assert.sh"
command -v hyprsunset >/dev/null || { echo "  skip hyprsunset render (not installed)"; exit 0; }
[ "$(date +%H:%M)" != 23:59 ] || { echo "  skip hyprsunset render (the day boundary is now)"; exit 0; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/cfg/hypr" "$tmp/run"
node --input-type=module -e '
import fs from "node:fs"
import * as O from "'"$root"'/scripts/state/overlay.mjs"
const text = fs.readFileSync(process.argv[1], "utf8")
const overrides = new Map([["day_time", "23:59"], ["night_time", "00:00"], ["night_temp", "3700"]])
process.stdout.write(O.layout("hyprvars", text, O.effective(O.parse("hyprvars", text), overrides, new Set())))
' "$root/defaults/hypr/hyprsunset.conf" > "$tmp/cfg/hypr/hyprsunset.conf"
sandbox() {
    env -u HYPRLAND_INSTANCE_SIGNATURE -u XDG_STATE_HOME XDG_CONFIG_HOME="$tmp/cfg" HOME="$tmp" \
        XDG_RUNTIME_DIR="$tmp/run" WAYLAND_DISPLAY=nope timeout 2 hyprsunset --verbose 2>&1 || true
}
out=$(sandbox)
assert_contains "$out" "Loaded 2 profiles" "both profiles parse through variables"
assert_contains "$out" "3700K" "the evening override is the applied temperature"
assert_not_contains "$out" "Config has errors" "the overridden file has no config errors"
assert_not_contains "$out" "exceeded max iteration" "no variable expands into itself"

# The defaults alone, no overrides: the 07:00 / 20:00 schedule decides.
cp "$root/defaults/hypr/hyprsunset.conf" "$tmp/cfg/hypr/hyprsunset.conf"
now=$(date +%H:%M)
if [ "$now" = 07:00 ] || [ "$now" = 20:00 ]; then
    echo "  skip default schedule (a boundary is now)"
else
    if [[ "$now" > 07:00 && "$now" < 20:00 ]]; then want=6000K; else want=4000K; fi
    out=$(sandbox)
    assert_contains "$out" "Loaded 2 profiles" "the defaults parse"
    assert_not_contains "$out" "Config has errors" "the defaults have no config errors"
    assert_not_contains "$out" "exceeded max iteration" "the defaults expand no variable into itself"
    assert_contains "$out" "temperature to $want" "the defaults apply the scheduled temperature at $now"
fi

# The panel's rules read the same defaults.
read -r day night temp < <(node --input-type=module -e '
import fs from "node:fs"
import * as O from "'"$root"'/scripts/state/overlay.mjs"
const m = O.parse("hyprvars", fs.readFileSync(process.argv[1], "utf8"))
console.log(m.get("day_time"), m.get("night_time"), m.get("night_temp"))
' "$root/defaults/hypr/hyprsunset.conf")
assert_eq "$day $night $temp" "07:00 20:00 4000" "the defaults declare day 07:00, evening 20:00, evening 4000K"
test_summary sunset-render
