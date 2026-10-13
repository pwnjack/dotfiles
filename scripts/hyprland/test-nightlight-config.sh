#!/bin/bash
#
# nightlight.sh reads the warm and neutral temperatures from the profiles of
# hyprsunset.conf, whether a profile names a literal or a hyprlang variable.
# The script runs against a fixture (NIGHTLIGHT_CONFIG) with hyprctl, hyprsunset,
# notify-send and pkill stubbed on PATH: no daemon, no display, no real bar.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TEST_DIR/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=scripts/lib/assert.sh
. "$ROOT/scripts/lib/assert.sh"

mkdir -p "$TMP/bin"
for stub in hyprsunset notify-send pkill; do printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/$stub"; done
printf '#!/bin/sh\necho "$@" >> "%s/calls"\n' "$TMP" > "$TMP/bin/hyprctl"
chmod +x "$TMP/bin"/*
export PATH="$TMP/bin:$PATH" HOME="$TMP/home"

# warm_and_neutral <fixture text>: the temperatures `on` and `off` apply.
temps() {
    printf '%s' "$1" > "$TMP/conf"
    : > "$TMP/calls"
    NIGHTLIGHT_CONFIG="$TMP/conf" bash "$ROOT/scripts/hyprland/nightlight.sh" on
    NIGHTLIGHT_CONFIG="$TMP/conf" bash "$ROOT/scripts/hyprland/nightlight.sh" off
    awk '{print $NF}' "$TMP/calls" | paste -sd' '
}

assert_eq "$(temps $'$day_time = 07:00\n$day_temp = 6500\n$night_time = 20:00\n$night_temp = 3700\nprofile {\n time = $day_time\n temperature = $day_temp\n}\nprofile {\n time = $night_time\n temperature = $night_temp\n}\n')" \
    "3700 6500" "variable profiles resolve to the configured temperatures"
assert_eq "$(temps $'profile {\n time = 07:00\n temperature = 6200\n}\nprofile {\n time = 20:00\n temperature = 3500\n}\n')" \
    "3500 6200" "literal profiles still work"
assert_eq "$(temps $'$night_temp = 3300 # evening\n$day_temp = 5900\nprofile {\n temperature = $day_temp # day\n}\nprofile {\n temperature = 4800 # literal\n}\nprofile {\n temperature = $night_temp\n}\n')" \
    "3300 5900" "a mix of literals, variables and inline comments"
assert_eq "$(temps $'profile {\n temperature = $missing\n}\n')" \
    "4000 6000" "an unresolvable variable falls back to the defaults"
test_summary nightlight-config
