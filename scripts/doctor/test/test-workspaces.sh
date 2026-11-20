# Tests for scripts/doctor/checks/workspaces.sh — sourced by run-tests.sh
# shellcheck shell=bash
#
# _wsm_home is redefined after sourcing so "~" in the fixture's include list
# resolves into the scratch dir instead of the real home directory.

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/waybar.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/workspaces.sh"

export DOCTOR_ROOT

wsm_real_current="$(declare -f _wsm_current)"

wsm_home="$DOCTOR_TEST_TMP/wsm-home"
_wsm_home() { printf '%s' "$wsm_home"; }

# wsm_fixture <modules-left entries...> -- a repo whose config.jsonc places them
wsm_fixture() {
    local entries="" e
    for e in "$@"; do entries="$entries\"$e\", "; done
    wsm_fixture_config "$(printf '{\n  "include": ["~/.local/state/waybar/bar.jsonc", "~/.local/state/waybar/workspaces.jsonc"],\n  "modules-left": [%s"clock"],\n  "cffi/workspaces": {},\n}' "$entries")"
}

# wsm_fixture_config <config body> -- a repo with exactly this config.jsonc
wsm_fixture_config() {
    local dir
    dir="$(make_fixture)" || return 1
    mkdir -p "$dir/waybar"
    printf '%s\n' "$1" > "$dir/waybar/config.jsonc"
    commit_fixture "$dir"
    printf '%s' "$dir"
}

# wsm_include <json> -- the rendered include in the fake home
wsm_include() {
    mkdir -p "$wsm_home/.local/state/waybar"
    printf '%s\n' "$1" > "$wsm_home/.local/state/waybar/workspaces.jsonc"
}

# wsm_reset -- every case starts from an empty fake home
wsm_reset() { rm -rf "$wsm_home"; mkdir -p "$wsm_home"; }

# --- no include: no module_path -----------------------------------------
wsm_reset
DOCTOR_ROOT="$(wsm_fixture "cffi/workspaces")"
run_check check_workspaces
assert_eq "$DOCTOR_ERRORS" "1" "a placed cffi module with no module_path is an ERROR"
assert_contains "$CHECK_OUT" "build-workspaces.sh" "the fix hint names the build script"

# --- module_path to a missing file --------------------------------------
wsm_reset
wsm_include '{"cffi/workspaces":{"module_path":"'"$wsm_home"'/lib/missing.so"}}'
run_check check_workspaces
assert_eq "$DOCTOR_ERRORS" "1" "a missing library is an ERROR"
assert_contains "$CHECK_OUT" "missing.so" "the finding names the library"

# --- stale library ------------------------------------------------------
wsm_reset
mkdir -p "$wsm_home/lib"
touch "$wsm_home/lib/workspaces.so"
wsm_include '{"cffi/workspaces":{"module_path":"'"$wsm_home"'/lib/workspaces.so"}}'
_wsm_current() { return 1; }
DOCTOR_ROOT="$(wsm_fixture "cffi/workspaces")"
run_check check_workspaces
assert_eq "$DOCTOR_ERRORS/$DOCTOR_WARNINGS" "0/1" "a library that does not match its sources is a WARN"
assert_contains "$CHECK_OUT" "previous build" "the warning says the bar runs an old build"

# --- up to date ---------------------------------------------------------
wsm_reset
mkdir -p "$wsm_home/lib"
touch "$wsm_home/lib/workspaces.so"
wsm_include '{"cffi/workspaces":{"module_path":"'"$wsm_home"'/lib/workspaces.so"}}'
DOCTOR_ROOT="$(wsm_fixture "cffi/workspaces")"
_wsm_current() { return 0; }
run_check check_workspaces
assert_eq "$DOCTOR_ERRORS/$DOCTOR_WARNINGS" "0/0" "an up-to-date library has no findings"
assert_contains "$CHECK_OUT" "every placed native module is built and current" "and prints the all-clear"

# --- nothing native placed ----------------------------------------------
wsm_reset
DOCTOR_ROOT="$(wsm_fixture "custom/media")"
run_check check_workspaces
assert_eq "$DOCTOR_ERRORS/$DOCTOR_WARNINGS" "0/0" "no cffi module placed has no findings"
assert_contains "$CHECK_OUT" "every placed native module is built and current" "the all-clear is accurate when none is placed"

# --- placed inside a group's "modules" array, no include ----------------
wsm_reset
DOCTOR_ROOT="$(wsm_fixture_config '{
  "modules-left": ["group/pill"],
  "group/pill": {
    "modules": ["clock", "cffi/workspaces"],
  },
}')"
run_check check_workspaces
assert_eq "$DOCTOR_ERRORS" "1" "a cffi module placed in a group with no module_path is an ERROR"

# --- two includes: the first one that sets the key wins -----------------
wsm_reset
mkdir -p "$wsm_home/lib" "$wsm_home/.local/state/waybar"
touch "$wsm_home/lib/first.so"
printf '%s\n' '{"cffi/workspaces":{"module_path":"'"$wsm_home"'/lib/first.so"}}' > "$wsm_home/.local/state/waybar/bar.jsonc"
wsm_include '{"cffi/workspaces":{"module_path":"'"$wsm_home"'/lib/second-missing.so"}}'
DOCTOR_ROOT="$(wsm_fixture "cffi/workspaces")"
_wsm_current() { return 0; }
run_check check_workspaces
assert_eq "$DOCTOR_ERRORS/$DOCTOR_WARNINGS" "0/0" "the first include's module_path is the one validated"

# --- multi-line include array with comments and $HOME -------------------
wsm_reset
mkdir -p "$wsm_home/lib"
touch "$wsm_home/lib/workspaces.so"
wsm_include '{"cffi/workspaces":{"module_path":"'"$wsm_home"'/lib/workspaces.so"}}'
DOCTOR_ROOT="$(wsm_fixture_config '{
  "include": [
    // rendered by build-workspaces.sh
    "$HOME/.local/state/waybar/workspaces.jsonc",
  ],
  "modules-left": ["cffi/workspaces"],
  "cffi/workspaces": {},
}')"
run_check check_workspaces
assert_eq "$DOCTOR_ERRORS/$DOCTOR_WARNINGS" "0/0" "a multi-line include array with comments and \$HOME/ resolves"

# --- config.jsonc sets module_path itself -------------------------------
wsm_reset
mkdir -p "$wsm_home/lib"
touch "$wsm_home/lib/workspaces.so"
wsm_include '{"cffi/workspaces":{"module_path":"'"$wsm_home"'/lib/workspaces.so"}}'
DOCTOR_ROOT="$(wsm_fixture_config '{
  "include": ["~/.local/state/waybar/workspaces.jsonc"],
  "modules-left": ["cffi/workspaces"],
  "cffi/workspaces": {
    "module_path": "/opt/ws.so",
  },
}')"
run_check check_workspaces
assert_eq "$DOCTOR_ERRORS" "1" "module_path set in config.jsonc is an ERROR"
assert_contains "$CHECK_OUT" "must not set module_path" "the finding says why"
assert_contains "$CHECK_OUT" "remove module_path" "the fix hint says what to remove"

# --- a commented-out module_path in config.jsonc is not a key ------------
wsm_reset
mkdir -p "$wsm_home/lib"
touch "$wsm_home/lib/workspaces.so"
wsm_include '{"cffi/workspaces":{"module_path":"'"$wsm_home"'/lib/workspaces.so"}}'
DOCTOR_ROOT="$(wsm_fixture_config '{
  "include": ["~/.local/state/waybar/workspaces.jsonc"],
  "modules-left": ["cffi/workspaces"],
  "cffi/workspaces": {
    // "module_path": "/old/path.so",
  },
}')"
_wsm_current() { return 0; }
run_check check_workspaces
assert_eq "$DOCTOR_ERRORS/$DOCTOR_WARNINGS" "0/0" "a commented-out module_path in config.jsonc is ignored"

# --- the string form of include, followed by more keys -------------------
wsm_reset
mkdir -p "$wsm_home/lib"
touch "$wsm_home/lib/workspaces.so"
wsm_include '{"cffi/workspaces":{"module_path":"'"$wsm_home"'/lib/workspaces.so"}}'
DOCTOR_ROOT="$(wsm_fixture_config '{
  "include": "~/.local/state/waybar/workspaces.jsonc",
  "position": "top",
  "modules-left": ["cffi/workspaces"],
  "cffi/workspaces": {},
}')"
assert_eq "$(_wsm_includes | wc -l)" "1" "the string form of include names exactly one file"
run_check check_workspaces
assert_eq "$DOCTOR_ERRORS/$DOCTOR_WARNINGS" "0/0" "and its module_path is found"

# --- relative module_path -----------------------------------------------
wsm_reset
wsm_include '{"cffi/workspaces":{"module_path":"lib/workspaces.so"}}'
DOCTOR_ROOT="$(wsm_fixture "cffi/workspaces")"
run_check check_workspaces
assert_eq "$DOCTOR_ERRORS" "1" "a relative module_path is an ERROR"
assert_contains "$CHECK_OUT" "not absolute" "the finding says it is not absolute"

# --- --check could not run ----------------------------------------------
wsm_reset
mkdir -p "$wsm_home/lib"
touch "$wsm_home/lib/workspaces.so"
wsm_include '{"cffi/workspaces":{"module_path":"'"$wsm_home"'/lib/workspaces.so"}}'
DOCTOR_ROOT="$(wsm_fixture "cffi/workspaces")"
_wsm_current() { echo "build-workspaces: sha256sum is not installed"; return 2; }
run_check check_workspaces
assert_eq "$DOCTOR_ERRORS/$DOCTOR_WARNINGS" "1/0" "a --check that cannot run is an ERROR"
assert_contains "$CHECK_OUT" "sha256sum is not installed" "the finding shows the script's message"

# --- the real _wsm_current against a fixture build script ---------------
eval "$wsm_real_current"
wsm_real_fixture() {
    local dir
    dir="$(wsm_fixture "cffi/workspaces")" || return 1
    mkdir -p "$dir/scripts/waybar" "$dir/waybar/workspaces"
    cp "$TEST_DIR/../../waybar/build-workspaces.sh" "$dir/scripts/waybar/build-workspaces.sh"
    printf 'all:\n' > "$dir/waybar/workspaces/Makefile"
    printf 'int x;\n' > "$dir/waybar/workspaces/a.c"
    printf '%s' "$dir"
}
# wsm_stamp <root> -- the stamp build-workspaces.sh computes, computed the same way
wsm_stamp() {
    {
        printf 'Makefile\0'; cat "$1/waybar/workspaces/Makefile"
        printf 'a.c\0'; cat "$1/waybar/workspaces/a.c"
        cat "$1/scripts/waybar/build-workspaces.sh"
    } | sha256sum | cut -d' ' -f1
}

wsm_reset
mkdir -p "$wsm_home/lib"
touch "$wsm_home/lib/workspaces.so"
wsm_include '{"cffi/workspaces":{"module_path":"'"$wsm_home"'/lib/workspaces.so"}}'
DOCTOR_ROOT="$(wsm_real_fixture)"
printf '%s\n' "$(wsm_stamp "$DOCTOR_ROOT")" > "$wsm_home/lib/workspaces.so.sha256"
run_check check_workspaces
assert_eq "$DOCTOR_ERRORS/$DOCTOR_WARNINGS" "0/0" "the real --check reports a matching stamp as current"

printf 'stale\n' > "$wsm_home/lib/workspaces.so.sha256"
run_check check_workspaces
assert_eq "$DOCTOR_ERRORS/$DOCTOR_WARNINGS" "0/1" "the real --check reports a mismatched stamp as a WARN"
assert_contains "$CHECK_OUT" "previous build" "and the warning says the bar runs an old build"

rm "$DOCTOR_ROOT/waybar/workspaces/Makefile"
run_check check_workspaces
assert_eq "$DOCTOR_ERRORS/$DOCTOR_WARNINGS" "1/0" "the real --check that cannot run is an ERROR"
assert_contains "$CHECK_OUT" "Makefile not found" "and shows the script's own message"
