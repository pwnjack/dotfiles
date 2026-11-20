#!/bin/bash
# Tests for scripts/keybinds/keybinds-sheet.sh: the JSON skin the Super+H
# overlay reads, the key vocabulary, and agreement between the skins.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHEET="$TEST_DIR/keybinds-sheet.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck disable=SC1091 # Shared assertions are checked by their own suite.
# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

cat > "$TMP/keybinds.lua" <<'LUA'
return function(apps)
    -- ## Media
    hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("v"), { locked = true }) -- Volume up
    hl.bind("XF86AudioPause", hl.dsp.exec_cmd("p")) -- Play/pause
    hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("p")) -- Play/pause
    hl.bind("XF86Calculator", hl.dsp.exec_cmd("c")) -- Calculator
    -- ## Mouse
    hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true }) -- Move window (drag)
    hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" })) -- Scroll through workspaces
    hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" })) -- Scroll through workspaces
    -- ## Quoting
    hl.bind("SUPER + SHIFT + Q", hl.dsp.window.close()) -- Say "hi" \ back
end
LUA

json=$(KEYBINDS_CONF="$TMP/keybinds.lua" bash "$SHEET" --json)
if printf '%s' "$json" | jq -e . >/dev/null 2>&1; then
    pass "fixture --json is valid JSON"
else
    fail "fixture --json is not valid JSON" "$json"
fi
assert_json_field "$json" '[.sections[].name] | join(",")' "Media,Mouse,Quoting" "sections keep file order"
assert_json_field "$json" '.sections[0].rows[0].keys | join("|")' "Volume Up" "media keys read as the key's legend"
assert_json_field "$json" '.sections[0].rows[1].keys | join("|")' "Play/Pause" "play and pause fold into one key, whatever the line order"
assert_json_field "$json" '.sections[0].rows[2].keys | join("|")' "Calculator" "unlisted XF86 keys drop the prefix"
assert_json_field "$json" '.sections[1].rows[0].keys | join("|")' "Super|Left button" "mouse:272 is the left button"
assert_json_field "$json" '.sections[1].rows[1].keys | join("|")' "Super|Wheel" "both wheel directions collapse to Wheel"
assert_json_field "$json" '.sections[2].rows[0].keys | join("|")' "Super|Shift|Q" "each modifier is its own key"
assert_json_field "$json" '.sections[2].rows[0].label' 'Say "hi" \ back' "quotes and backslashes survive JSON"

# Escaping beyond quotes, a bind above the first heading, and an empty config.
tab=$'\t'
ctl=$'\x01'
cat > "$TMP/edge.lua" <<LUA
return function(apps)
    hl.bind("SUPER + X", hl.dsp.exec_cmd("x")) -- Before${tab}any${ctl} heading
end
LUA
edge=$(KEYBINDS_CONF="$TMP/edge.lua" bash "$SHEET" --json)
assert_json_field "$edge" '.sections[0].name' "Other" "a bind above every heading lands in Other"
assert_json_field "$edge" '.sections[0].rows[0].label' "Before${tab}any heading" "tabs survive and control characters are dropped"
printf 'return function(apps)\nend\n' > "$TMP/empty.lua"
assert_eq "$(KEYBINDS_CONF="$TMP/empty.lua" bash "$SHEET" --json)" '{"sections":[]}' "an empty config is an empty sheet"

real_json=$(bash "$SHEET" --json)
if printf '%s' "$real_json" | jq -e . >/dev/null 2>&1; then
    pass "keybinds.lua renders valid JSON"
else
    fail "keybinds.lua renders invalid JSON" "$real_json"
fi

for args in "" "--rofi"; do
    # shellcheck disable=SC2086 # The empty case must pass no argument at all.
    err=$(bash "$SHEET" $args 2>&1 >/dev/null)
    status=$?
    assert_eq "$status" "2" "'${args:-no arguments}' exits 2"
    assert_contains "$err" "Usage:" "'${args:-no arguments}' prints usage"
done

test_summary
