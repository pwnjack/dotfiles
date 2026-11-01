# Tests for scripts/doctor/checks/waybar.sh — sourced by run-tests.sh
#
# Sourced fragment, never executed directly, so it carries no shebang; the
# directive below tells shellcheck which shell to assume (SC2148).
# shellcheck shell=bash
#
# Checks are run ONCE, redirected to a file under $DOCTOR_TEST_TMP, and the
# output is read back. `out="$(check_x)"` would run the check in a subshell and
# discard its severity counters.
#
# _way_have_cmd is shadowed by a function rather than by manipulating PATH: the
# check runs in this shell, so a definition here wins, and the test then does
# not depend on what happens to be installed on the machine running it.

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/waybar.sh"

# Assigned throughout this file but read only by the check sourced above.
export DOCTOR_ROOT

way_out_file="$DOCTOR_TEST_TMP/waybar.out"

# Only these two resolve; everything else the fixtures name does not.
_way_have_cmd() {
    case "$1" in
        installed-tool|hyprctl|/opt/present/tool) return 0 ;;
        *) return 1 ;;
    esac
}

# way_config <root> <body> — write a config.jsonc into a fixture repo.
way_config() {
    mkdir -p "$1/waybar"
    printf '%s\n' "$2" > "$1/waybar/config.jsonc"
}

# --- a config exercising every finding ------------------------------------
way_fixture="$(make_fixture)"
way_config "$way_fixture" '{
  "layer": "bottom",
  "spacing": 0,

  // inline form, as modules-left is written in the real config
  "modules-left": ["hyprland/window", "custom/orphaned"],

  // A commented-out entry and NO bracket in any comment, so this array
  // isolates the // strip: hyprland/window is placed in modules-left too, so
  // dropping this whole array changes nothing and only the phantom shows.
  "modules-center": [
    // "custom/commented-out",
    "hyprland/window",
  ],

  // multi-line form, and the bracket in the comment below closes the array
  // early unless // is stripped before the closing bracket is looked for.
  // Nothing here is commented out, so this array isolates the bracket test.
  "modules-right": [
    // pinned in this order, see notes[1]
    "clock",
    "typoed-builtin",
    "custom/media",
  ],

  "hyprland/window": {
    "format": "{}",
  },

  "clock": {
    "on-click": "installed-tool",
    "on-click-right": "/opt/present/tool",
    // nested OBJECT-valued keys, as the real clock block nests them. A scalar
    // "format": "{}" would be excluded by the { requirement whatever the
    // indent rule was, so it could not tell a correct rule from a broken one.
    "calendar": {
      "format": {
        "months": "{}",
      },
    },
    "actions": {
      "on-click-middle": "mode",
      "on-scroll-up": "shift_up",
      "on-scroll-down": "shift_down",
    },
  },

  "custom/media": {
    "exec": "~/.config/scripts/hyprland/mediaexec.sh",
    "on-click-right": "$HOME/.config/scripts/hyprland/mediactl.sh",
    "on-click": "missing-tool",
    "on-click-middle": "/opt/absent/tool",
    "on-scroll-up": "hyprctl dispatch '\''hl.dsp.focus({ workspace = \"r-1\" })'\''",
  },

  "unplaced-block": {
    "format": "{}",
  },
}'

DOCTOR_ROOT="$way_fixture"
doctor_reset
check_waybar > "$way_out_file" 2>&1
way_out="$(<"$way_out_file")"

# --- placed but unconfigured ----------------------------------------------
assert_contains "$way_out" "custom/orphaned" "a custom module with no block is reported"
assert_contains "$way_out" "ERROR" "a custom module with no block is ERROR severity"
assert_contains "$way_out" "typoed-builtin" "a built-in with no block is reported"
assert_not_contains "$way_out" "hyprland/window but" \
    "a module that is both placed and configured is not reported as an orphan"

# --- JSONC comments inside a modules array are not data --------------------
# A commented-out custom/* name is an ERROR if it is read as placed, which is
# doctor.sh exiting 1 on a bar that works. And the "notes[1]" comment above
# "clock" closes the array early unless // is stripped first, which would drop
# every module below it and orphan all three of their blocks.
assert_not_contains "$way_out" "custom/commented-out" "a commented-out module is not read as placed"
assert_not_contains "$way_out" "configures clock but" "a bracket in a comment does not close the array early"
assert_not_contains "$way_out" "configures custom/media but" "modules after a comment bracket stay placed"

# --- configured but unplaced ----------------------------------------------
assert_contains "$way_out" "unplaced-block" "a block in no modules list is reported"
assert_contains "$way_out" "INFO" "an unplaced block is INFO severity"

# --- handler binaries -----------------------------------------------------
assert_contains "$way_out" "missing-tool" "an uninstalled handler binary is reported"
assert_not_contains "$way_out" "installed-tool" "an installed handler binary produces no finding"
assert_not_contains "$way_out" "hyprctl" "only the first token of a handler is checked"
assert_not_contains "$way_out" "mediaexec.sh" "a ~/.config handler is left to references.sh"
assert_not_contains "$way_out" "mediactl.sh" 'a $HOME/.config handler is left to references.sh too'

# An absolute handler goes through _way_have_cmd like any other token, so both
# outcomes are reachable through the stub -- a hand-rolled [ -x ] branch would
# bypass the seam and pass a directory as if it were a program.
assert_contains "$way_out" "/opt/absent/tool" "an absolute handler that does not resolve is reported"
assert_not_contains "$way_out" "/opt/present/tool" "an absolute handler that resolves produces no finding"

# --- waybar's own action vocabulary ---------------------------------------
# These sit where a command would and resolve nowhere; without the skip set
# they are five warnings on a healthy machine.
assert_not_contains "$way_out" "mode," "an action keyword is not read as a command"
assert_not_contains "$way_out" "shift_up" "shift_up is not read as a command"
assert_not_contains "$way_out" "shift_down" "shift_down is not read as a command"

# --- nested keys are not config blocks ------------------------------------
# "calendar", "format" and "actions" are object-valued keys nested inside
# clock; reading them as top-level blocks would report all three as unplaced.
assert_not_contains "$way_out" "configures calendar" "a nested key is not read as a config block"
assert_not_contains "$way_out" "configures format" "a doubly-nested key is not read as a config block"
assert_not_contains "$way_out" "configures actions" "an actions sub-block is not read as a config block"

assert_eq "$DOCTOR_ERRORS" "1" "one custom module without a block counted as an error"
assert_eq "$DOCTOR_WARNINGS" "3" "the typoed built-in and both missing binaries counted as warnings"
assert_eq "$DOCTOR_NOTICES" "1" "one unplaced block counted as a notice"

# --- fix hints ------------------------------------------------------------
assert_contains "$way_out" "$way_fixture/waybar/config.jsonc" "hints name the config file"
assert_not_contains "$way_out" "<" "no hint contains what a shell reads as a redirection"

# The bug this catches: an unquoted config path with a space is two arguments
# to whatever the hint tells the reader to run. Fixture paths hold no
# metacharacters, so every other assertion here passes with doctor_q deleted --
# test-symlinks.sh records that this exact gap once survived review.
# check_waybar never shells out to git, so the root does not have to be a repo.
way_spaced="$(make_fixture)/spaced root"
mkdir -p "$way_spaced"
way_config "$way_spaced" '{
  "modules-left": ["custom/orphaned"],
}'

DOCTOR_ROOT="$way_spaced"
doctor_reset
check_waybar > "$way_out_file" 2>&1
way_spaced_out="$(<"$way_out_file")"

assert_contains "$way_spaced_out" "spaced\\ root/waybar/config.jsonc" \
    "hints shell-quote a config path containing a space"

# Doubles as the ERROR arm of the ok gate: one error, nothing else. With the
# error arm neutered the other two arms are both satisfied and print a tick.
assert_not_contains "$way_spaced_out" "✓" "an error-only config gets no green tick"
assert_eq "$DOCTOR_ERRORS$DOCTOR_WARNINGS$DOCTOR_NOTICES" "100" "an error-only config records exactly one error"

# --- a clean config gets the all-clear ------------------------------------
way_clean="$(make_fixture)"
way_config "$way_clean" '{
  "modules-left": ["clock"],
  "clock": {
    "on-click": "installed-tool",
  },
}'

DOCTOR_ROOT="$way_clean"
doctor_reset
check_waybar > "$way_out_file" 2>&1
way_clean_out="$(<"$way_out_file")"

assert_contains "$way_clean_out" "✓" "a clean config gets the green tick"
assert_eq "$DOCTOR_ERRORS$DOCTOR_WARNINGS$DOCTOR_NOTICES" "000" "a clean config records no findings"
assert_not_contains "$way_out" "✓" "a config with findings gets no green tick"

# --- each arm of the ok gate, isolated ------------------------------------
# The main fixture records all three severities, so any two surviving arms hide
# the third: neutering one arm there still leaves the tick suppressed, for the
# wrong reason. Only a fixture recording exactly one severity tests that
# severity's arm. The ERROR arm is covered by way_spaced above; here are the
# other two.
way_warnonly="$(make_fixture)"
way_config "$way_warnonly" '{
  "modules-left": ["clock"],
  "clock": {
    "on-click": "missing-tool",
  },
}'

DOCTOR_ROOT="$way_warnonly"
doctor_reset
check_waybar > "$way_out_file" 2>&1
way_warnonly_out="$(<"$way_out_file")"

assert_not_contains "$way_warnonly_out" "✓" "a warning-only config gets no green tick"
assert_eq "$DOCTOR_ERRORS$DOCTOR_WARNINGS$DOCTOR_NOTICES" "010" "a warning-only config records exactly one warning"

# The notice-only case is the shape of the live repo: one orphaned block, no
# errors and no warnings. Gating ok on the error count alone would print a
# green tick right above it.
way_notice="$(make_fixture)"
way_config "$way_notice" '{
  "modules-left": ["clock"],
  "clock": {
    "on-click": "installed-tool",
  },
  "unplaced-block": {
    "format": "{}",
  },
}'

DOCTOR_ROOT="$way_notice"
doctor_reset
check_waybar > "$way_out_file" 2>&1
way_notice_out="$(<"$way_out_file")"

assert_not_contains "$way_notice_out" "✓" "a notice-only config gets no green tick"
assert_eq "$DOCTOR_ERRORS$DOCTOR_WARNINGS$DOCTOR_NOTICES" "001" "a notice-only config records exactly one notice"

# --- no waybar config at all ----------------------------------------------
# Not an error: DOCTOR_ROOT may be a fixture or a partial clone, and the
# absence of a bar is not a broken bar.
way_bare="$(make_fixture)"
DOCTOR_ROOT="$way_bare"
doctor_reset
check_waybar > "$way_out_file" 2>&1
way_bare_out="$(<"$way_out_file")"

assert_contains "$way_bare_out" "nothing to check" "a repo without a waybar config says so"
assert_eq "$DOCTOR_ERRORS$DOCTOR_WARNINGS" "00" "a missing waybar config is not an error or warning"

# --- group members are placed ---------------------------------------------
# A group lists its members in its own "modules" array. Reading only the
# modules-* arrays would report every member block as unplaced.
way_group_fixture="$(make_fixture)"
way_config "$way_group_fixture" '{
  "modules-right": ["group/res"],
  "group/res": {
    "orientation": "horizontal",
    "modules": ["cpu", "memory"],
  },
  "cpu": { "interval": 3 },
  "memory": { "interval": 3 },
}'
DOCTOR_ROOT="$way_group_fixture"
doctor_reset
check_waybar > "$way_out_file" 2>&1
way_group_out="$(<"$way_out_file")"
assert_not_contains "$way_group_out" "configures cpu but" "a module inside a group is placed"
assert_not_contains "$way_group_out" "configures group/res but" "the group itself is placed"

# --- only a group's "modules" places anything ------------------------------
# The privacy module also has a "modules" key, holding objects whose "type"
# names a stream kind, not a bar module. Reading it as placed modules reported
# audio-in and screenshare as unconfigured.
way_privacy_fixture="$(make_fixture)"
way_config "$way_privacy_fixture" '{
  "modules-right": ["privacy"],
  "privacy": {
    "modules": [
      { "type": "screenshare", "tooltip-icon-size": 20 },
      { "type": "audio-in" },
    ],
  },
}'
DOCTOR_ROOT="$way_privacy_fixture"
doctor_reset
check_waybar > "$way_out_file" 2>&1
way_privacy_out="$(<"$way_out_file")"
assert_not_contains "$way_privacy_out" "audio-in" "a privacy stream type is not a placed module"
assert_not_contains "$way_privacy_out" "screenshare" "a privacy stream type is not a placed module"
assert_eq "$DOCTOR_ERRORS$DOCTOR_WARNINGS" "00" "a configured privacy module is clean"
