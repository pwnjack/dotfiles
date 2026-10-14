#!/bin/bash
#
# Tests for scripts/waybar/bar-modes.sh, run as a subprocess the way the
# settings panel and install.sh run it. BAR_OPTIONS and BAR_INCLUDE are the
# seam; a fake pkill on PATH records the reload.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/bar-modes.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck disable=SC1091 # Shared assertions are checked by their own suite.
# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

mkdir -p "$TMP/opt" "$TMP/bin"
printf '#!/bin/bash\necho "$*" >> "%s/pkill.log"\n' "$TMP" > "$TMP/bin/pkill"
# A running bar, and a busctl that registers nothing, so the reload through
# waybar.sh never reaches the real session's tray.
printf '#!/bin/bash\nexit "${PGREP_STATUS:-0}"\n' > "$TMP/bin/pgrep"
printf '#!/bin/bash\nexit 0\n' > "$TMP/bin/busctl"
chmod +x "$TMP/bin/pkill" "$TMP/bin/pgrep" "$TMP/bin/busctl"

# render [--no-reload] — run the script, print the include
render() {
    BAR_OPTIONS="$TMP/opt" BAR_INCLUDE="$TMP/out/bar.jsonc" BAR_CSS="$TMP/out/bar.css" PATH="$TMP/bin:$PATH" \
        bash "$SCRIPT" "$@"
    cat "$TMP/out/bar.jsonc"
}

# mods — the include without the layout keys, for the per-module assertions
mods() { jq -c 'del(.position, .["margin-top"], .["margin-bottom"], .["margin-left"], .["margin-right"], .output)'; }

# set_mode <module> <value>
set_mode() { printf '%s\n' "$2" > "$TMP/opt/bar-$1"; }

out=$(render --no-reload)
assert_eq "$(mods <<< "$out")" '{}' "no option files render an empty include"

set_mode cpu always; set_mode memory banana; set_mode disk always
out=$(render --no-reload)
assert_eq "$(mods <<< "$out")" '{}' "always and garbage values both mean always"

set_mode cpu high
out=$(render --no-reload)
assert_eq "$(mods <<< "$out")" '{"cpu":{"format-normal":""}}' "high blanks only the normal state"

set_mode cpu always; set_mode disk hidden
out=$(render --no-reload)
assert_eq "$(mods <<< "$out")" '{"disk":{"format-normal":"","format-warning":"","format-critical":""}}' "hidden blanks every state"

set_mode cpu high; set_mode memory hidden; set_mode disk high
out=$(render --no-reload)
assert_eq "$(mods <<< "$out" | jq -c 'keys')" '["cpu","disk","memory"]' "each module is rendered independently"

assert_eq "$(find "$TMP/out" -name 'bar.jsonc.*' | wc -l)" 0 "no temporary file is left behind"
if [ -e "$TMP/pkill.log" ]; then
    fail "--no-reload does not signal Waybar"
else
    pass "--no-reload does not signal Waybar"
fi
render > /dev/null
assert_eq "$(<"$TMP/pkill.log")" "-USR2 -x waybar" "a render signals Waybar once"
rm -f "$TMP/pkill.log"
PGREP_STATUS=1 render > /dev/null
if [ -e "$TMP/pkill.log" ]; then
    fail "a bar that is not running is neither started nor signalled"
else
    pass "a bar that is not running is neither started nor signalled"
fi

# ── layout options ────────────────────────────────────────────────────
rm -rf "$TMP/opt"; mkdir -p "$TMP/opt"
# layout — margins as "top bottom left right" from the last render
layout() { jq -r '[.position, .["margin-top"], .["margin-bottom"], .["margin-left"], .["margin-right"], (.output // "none")] | join(" ")' "$TMP/out/bar.jsonc"; }
css() { tr '\n' ' ' < "$TMP/out/bar.css" | tr -s ' '; }
opt() { printf '%s\n' "$2" > "$TMP/opt/bar-$1"; }
rule() { printf 'window#waybar { background: alpha(@background, %s); %s border-radius: %spx; } ' "$1" "$2" "$3" | tr -s ' '; }
FULL='border: 1px solid @foreground;'

render --no-reload > /dev/null
assert_eq "$(layout)" "top 8 0 10 10 none" "defaults reproduce today's margins"
assert_eq "$(css)" "$(rule 0.80 "$FULL" 18)" "defaults reproduce today's stylesheet"

opt position bottom
render --no-reload > /dev/null
assert_eq "$(layout)" "bottom 0 8 10 10 none" "floating on the bottom flips the edge margin"
assert_eq "$(css)" "$(rule 0.80 "$FULL" 18)" "floating stylesheet is position independent"

opt style docked
render --no-reload > /dev/null
assert_eq "$(layout)" "bottom 0 0 0 0 none" "docked has no margins"
assert_eq "$(css)" "$(rule 0.80 'border-top: 1px solid @foreground;' 0)" "docked bottom bar borders its top edge"
opt position top
render --no-reload > /dev/null
assert_eq "$(css)" "$(rule 0.80 'border-bottom: 1px solid @foreground;' 0)" "docked top bar borders its bottom edge"

opt border disabled
render --no-reload > /dev/null
assert_eq "$(css)" "$(rule 0.80 '' 0)" "border disabled removes it when docked"
opt style floating
render --no-reload > /dev/null
assert_eq "$(css)" "$(rule 0.80 '' 18)" "border disabled removes it when floating"
opt border enabled

for pair in 0:0.00 5:0.05 50:0.50 100:1 007:0.07 105:0.80 abc:0.80 -5:0.80 5.5:0.80 '':0.80 \
    18446744073709551616:0.80 9223372036854775808:0.80; do
    opt opacity "${pair%%:*}"
    render --no-reload > /dev/null
    assert_contains "$(css)" "alpha(@background, ${pair#*:});" "opacity '${pair%%:*}' renders ${pair#*:}"
done
opt opacity 80

opt output DP-1
render --no-reload > /dev/null
assert_eq "$(layout)" "top 8 0 10 10 DP-1" "a named output is written"
opt output 'bad"name'
render --no-reload > /dev/null
assert_eq "$(jq 'has("output")' "$TMP/out/bar.jsonc")" false "an unsafe output name writes no key"
opt output ''
render --no-reload > /dev/null
assert_eq "$(jq 'has("output")' "$TMP/out/bar.jsonc")" false "an empty output writes no key"

assert_eq "$(find "$TMP/out" -name 'bar.*.*' | wc -l)" 0 "no temporary file is left behind by any render"
[ -s "$TMP/out/bar.jsonc" ] && [ -s "$TMP/out/bar.css" ] && pass "both outputs exist" || fail "both outputs exist"

config="$TEST_DIR/../../waybar/config.jsonc"
# shellcheck disable=SC2088 # The literal tilde is present in Waybar's config.
assert_contains "$(grep '"include"' "$config")" '~/.local/state/waybar/bar.jsonc' "config.jsonc includes the rendered file"
if sed -n '/^  "\(cpu\|memory\|disk\)": {/,/^  },/p' "$config" | grep -Eq '"format-(normal|warning|critical)"'; then
    fail "config.jsonc must not set the per-state formats bar.jsonc controls"
else
    pass "config.jsonc leaves the per-state formats to the include"
fi

for key in position margin-top margin-bottom margin-left margin-right output; do
    if grep -Eq "^[[:space:]]*\"$key\"" "$config"; then
        fail "config.jsonc must not set $key"
    else
        pass "config.jsonc leaves $key to the include"
    fi
done
style="$TEST_DIR/../../waybar/style.css"
assert_contains "$(grep -n '@import' "$style")" '@import "bar.css"' "style.css imports bar.css"
if [ "$(grep -n '@import "../../.cache/wal/colors-waybar.css"' "$style" | cut -d: -f1)" -lt "$(grep -n '@import "bar.css"' "$style" | cut -d: -f1)" ]; then
    pass "bar.css is imported after the palette colours"
else
    fail "bar.css is imported after the palette colours"
fi
if sed -n '/^window#waybar {/,/^}/p' "$style" | grep -Eq 'background|border'; then
    fail "style.css must not set the bar's background, border or radius"
else
    pass "style.css leaves the bar's look to bar.css"
fi

test_summary test-bar-modes
