# Tests for scripts/doctor/checks/hyprctl.sh — sourced by run-tests.sh
# shellcheck shell=bash

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/waybar.sh"   # _way_placed, as doctor.sh loads it first
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/hyprctl.sh"

export DOCTOR_ROOT


# --- every removed runtime form is reported -------------------------------
hctl_fixture="$(make_fixture)"
mkdir -p "$hctl_fixture/hypr" "$hctl_fixture/ags" "$hctl_fixture/docs" \
    "$hctl_fixture/scripts/doctor"
printf 'require("config")\n' > "$hctl_fixture/hypr/hyprland.lua"
printf '%s\n' \
    'hyprctl dispatch workspace r-1' \
    'hyprctl keyword misc:vrr 1' \
    'hyprctl dispatch '\''hl.dsp.exit()'\''' \
    'hyprctl eval '\''hl.config({ misc = { vrr = 1 } })'\''' \
    '# hyprctl dispatch exit is only a comment' \
    > "$hctl_fixture/actions.sh"
printf '%s\n' \
    'execAsync(["hyprctl", "dispatch", "exec", command])' \
    'execAsync(["hyprctl", "keyword", keyword, value])' \
    'execAsync(["hyprctl", "dispatch", "hl.dsp.exit()"])' \
    '// execAsync(["hyprctl", "dispatch", "exit"]) is only a comment' \
    > "$hctl_fixture/ags/panel.ts"
printf 'hyprctl dispatch exit\n' > "$hctl_fixture/docs/legacy-example.txt"
printf 'hyprctl keyword misc:vrr 1\n' > "$hctl_fixture/scripts/doctor/fixture.sh"
commit_fixture "$hctl_fixture"

DOCTOR_ROOT="$hctl_fixture"
run_check check_hyprctl

assert_contains "$CHECK_OUT" "actions.sh:1" "a positional shell dispatcher is reported"
assert_contains "$CHECK_OUT" "actions.sh:2" "hyprctl keyword is reported"
assert_contains "$CHECK_OUT" "ags/panel.ts:1" "a positional dispatcher array is reported"
assert_contains "$CHECK_OUT" "ags/panel.ts:2" "a keyword array is reported"
assert_not_contains "$CHECK_OUT" "actions.sh:3" "a Lua dispatcher expression is accepted"
assert_not_contains "$CHECK_OUT" "actions.sh:4" "hyprctl eval is accepted"
assert_not_contains "$CHECK_OUT" "actions.sh:5" "a shell comment is ignored"
assert_not_contains "$CHECK_OUT" "ags/panel.ts:3" "a Lua dispatcher array is accepted"
assert_not_contains "$CHECK_OUT" "ags/panel.ts:4" "a TypeScript comment is ignored"
assert_not_contains "$CHECK_OUT" "legacy-example" "documentation examples are excluded"
assert_not_contains "$CHECK_OUT" "fixture.sh" "the doctor's own fixtures are excluded"
assert_eq "$DOCTOR_ERRORS$DOCTOR_WARNINGS$DOCTOR_NOTICES" "040" \
    "the four removed calls are warnings"
assert_not_contains "$CHECK_OUT" "✓" "a compatibility warning suppresses the green tick"
assert_contains "$CHECK_OUT" "$hctl_fixture/actions.sh" "the fix hint names the source file"

# --- the scan is gated by the tracked provider ----------------------------
hctl_legacy="$(make_fixture)"
printf 'hyprctl dispatch workspace 1\n' > "$hctl_legacy/actions.sh"
commit_fixture "$hctl_legacy"

DOCTOR_ROOT="$hctl_legacy"
run_check check_hyprctl

assert_contains "$CHECK_OUT" "does not use Hyprland's Lua provider" \
    "a legacy-provider tree is explicitly skipped"
assert_not_contains "$CHECK_OUT" "WARN" "legacy syntax is allowed with the legacy provider"
assert_eq "$DOCTOR_ERRORS$DOCTOR_WARNINGS$DOCTOR_NOTICES" "000" \
    "a skipped legacy-provider tree records no findings"

# --- Waybar's implicit positional dispatcher is reported -----------------
hctl_waybar="$(make_fixture)"
mkdir -p "$hctl_waybar/hypr" "$hctl_waybar/waybar"
printf 'return {}\n' > "$hctl_waybar/hypr/hyprland.lua"
printf '%s\n' \
    '{' \
    '  "modules-center": [' \
    '    // "hyprland/workspaces",' \
    '    "hyprland/workspaces",' \
    '  ],' \
    '}' \
    > "$hctl_waybar/waybar/config.jsonc"
commit_fixture "$hctl_waybar"

DOCTOR_ROOT="$hctl_waybar"
run_check check_hyprctl

assert_contains "$CHECK_OUT" "hyprland/workspaces" \
    "Waybar's implicit positional workspace dispatcher is reported"
assert_contains "$CHECK_OUT" "replace it with cffi/workspaces" \
    "the Waybar finding names the native replacement"
assert_eq "$DOCTOR_ERRORS$DOCTOR_WARNINGS$DOCTOR_NOTICES" "010" \
    "the incompatible Waybar module is one warning"
assert_not_contains "$CHECK_OUT" "✓" \
    "an incompatible Waybar module suppresses the green tick"

# --- a clean Lua-provider tree gets the all-clear -------------------------
hctl_clean="$(make_fixture)"
mkdir -p "$hctl_clean/hypr" "$hctl_clean/waybar"
printf 'return {}\n' > "$hctl_clean/hypr/hyprland.lua"
printf '%s\n' \
    'hyprctl dispatch '\''hl.dsp.focus({ workspace = "r-1" })'\''' \
    'hyprctl eval '\''hl.config({ misc = { vrr = 0 } })'\''' \
    > "$hctl_clean/actions.sh"
printf '%s\n' \
    '{' \
    '  "modules-center": [' \
    '    // "hyprland/workspaces",' \
    '    "ext/workspaces",' \
    '  ],' \
    '  "hyprland/workspaces": {' \
    '    "on-click": "activate",' \
    '  },' \
    '}' \
    > "$hctl_clean/waybar/config.jsonc"
commit_fixture "$hctl_clean"

DOCTOR_ROOT="$hctl_clean"
run_check check_hyprctl

assert_contains "$CHECK_OUT" "✓" "a compatible Lua-provider tree gets the green tick"
assert_not_contains "$CHECK_OUT" "hyprland/workspaces, whose clicks" \
    "a commented or configured-but-unplaced native module is accepted"
assert_eq "$DOCTOR_ERRORS$DOCTOR_WARNINGS$DOCTOR_NOTICES" "000" \
    "a compatible tree records no findings"
