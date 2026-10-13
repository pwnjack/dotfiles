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
out=$(env XDG_CONFIG_HOME="$tmp/cfg" HOME="$tmp" XDG_RUNTIME_DIR="$tmp/run" WAYLAND_DISPLAY=nope \
    timeout 2 hyprsunset --verbose 2>&1 || true)
assert_contains "$out" "Loaded 2 profiles" "both profiles parse through variables"
assert_contains "$out" "3700K" "the evening override is the applied temperature"
test_summary sunset-render
