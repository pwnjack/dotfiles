# Tests for scripts/doctor/checks/state.sh — sourced by run-tests.sh
# shellcheck shell=bash

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/state.sh"

st_root="$DOCTOR_TEST_TMP/state-repo"
mkdir -p "$st_root/defaults/options" "$st_root/defaults/gtk-3.0" "$st_root/options" "$st_root/gtk-3.0" "$st_root/scripts/state"
cp "$DOCTOR_DIR/../state/overlay.mjs" "$DOCTOR_DIR/../state/overlay-cli.mjs" "$st_root/scripts/state/"
printf 'zen\n' > "$st_root/defaults/options/browser"
printf 'nvim\n' > "$st_root/defaults/options/editor"
printf '[Settings]\na=1\n' > "$st_root/defaults/gtk-3.0/settings.ini"
printf 'x\n' > "$st_root/defaults/options/.hidden"
printf 'options/*\ngtk-3.0/settings.ini\n*.overlay-tmp\n' > "$st_root/.gitignore"
git -C "$st_root" init -q
git -C "$st_root" add .gitignore defaults scripts
# Editor leftovers beside the defaults are not targets, as in overlay-cli.mjs.
printf 'old\n' > "$st_root/defaults/gtk-3.0/settings.ini~"
printf 'old\n' > "$st_root/defaults/options/#browser#"
# options/ is one target: the overlay reads only the files directly inside it.
mkdir -p "$st_root/defaults/options/nested"
printf 'x\n' > "$st_root/defaults/options/nested/unused"
printf 'zen\n' > "$st_root/options/browser"          # editor missing
printf '[Settings]\na=1\n' > "$st_root/gtk-3.0/settings.ini"
git -C "$st_root" add -f gtk-3.0/settings.ini        # tracked by mistake
st_state="$DOCTOR_TEST_TMP/state-dir"
mkdir -p "$st_state/overrides/gtk-3.0"
printf 'garbage\n' > "$st_state/overrides/gtk-3.0/settings.ini"

st_saved_root="$DOCTOR_ROOT" st_saved_home="$HOME" st_saved_xdg="${XDG_STATE_HOME:-}"
DOCTOR_ROOT="$st_root" DOCTOR_STATE_DIR="$st_state" XDG_STATE_HOME="/elsewhere" HOME="$DOCTOR_TEST_TMP"
doctor_reset
check_state > "$DOCTOR_TEST_TMP/state.out" 2>&1
st_text="$(cat "$DOCTOR_TEST_TMP/state.out")"
assert_eq "$DOCTOR_ERRORS" "2" "state: missing render and tracked live file"
assert_eq "$DOCTOR_WARNINGS" "2" "state: bad overrides and XDG_STATE_HOME"
assert_contains "$st_text" "options/editor" "state: names the missing option"
assert_contains "$st_text" "gtk-3.0/settings.ini" "state: names the tracked live file"
assert_not_contains "$st_text" ".hidden" "state: dot-files are not targets"
assert_not_contains "$st_text" "settings.ini~" "state: editor backups are not targets"
assert_not_contains "$st_text" "#browser#" "state: editor autosaves are not targets"
assert_not_contains "$st_text" "nested" "state: a directory inside options/ is not a target"
assert_contains "$st_text" "Overrides file does not parse: gtk-3.0/settings.ini" "state: names the bad overrides file"
assert_not_contains "$st_text" "✓" "state: no all-clear when something was found"

# Clean tree: everything rendered, untracked, ignored, no overrides, default state home.
git -C "$st_root" rm -q --cached gtk-3.0/settings.ini
printf 'nvim\n' > "$st_root/options/editor"
rm -rf "$st_state"
DOCTOR_STATE_DIR="$st_state" XDG_STATE_HOME="" HOME="$DOCTOR_TEST_TMP"
doctor_reset
check_state > "$DOCTOR_TEST_TMP/state.out" 2>&1
assert_eq "$((DOCTOR_ERRORS + DOCTOR_WARNINGS))" "0" "state: a synced tree is clean"
assert_contains "$(cat "$DOCTOR_TEST_TMP/state.out")" "✓" "state: prints the all-clear when nothing is found"

# A live file that does not parse: every sync skips it, so it is reported.
printf '[Settings]\nnot a pair\n' > "$st_root/gtk-3.0/settings.ini"
doctor_reset
check_state > "$DOCTOR_TEST_TMP/state.out" 2>&1
st_text="$(cat "$DOCTOR_TEST_TMP/state.out")"
assert_eq "$DOCTOR_ERRORS.$DOCTOR_WARNINGS" "0.1" "state: a malformed live file is a warning"
assert_contains "$st_text" "Live file does not parse, so every sync skips it: gtk-3.0/settings.ini: line 2" "state: names the malformed live file"
printf '[Settings]\na=1\n' > "$st_root/gtk-3.0/settings.ini"

# A crash between write and rename leaves the overlay's temporary file holding
# this machine's settings; git must never offer to track it.
printf 'options/*\ngtk-3.0/settings.ini\n' > "$st_root/.gitignore"
doctor_reset
check_state > "$DOCTOR_TEST_TMP/state.out" 2>&1
st_text="$(cat "$DOCTOR_TEST_TMP/state.out")"
assert_eq "$DOCTOR_ERRORS" "1" "state: an unignored temporary file is an error"
assert_contains "$st_text" "gtk-3.0/.settings.ini.overlay-tmp" "state: names the temporary file"
assert_not_contains "$st_text" ".browser.overlay-tmp" "state: a temporary file already ignored is fine"

# An unanchored ignore rule that would hide a defaults/ file.
printf 'options/*\ngtk-3.0/settings.ini\n*.overlay-tmp\nsettings.ini\n' > "$st_root/.gitignore"
doctor_reset
check_state > "$DOCTOR_TEST_TMP/state.out" 2>&1
assert_eq "$DOCTOR_ERRORS" "1" "state: a defaults file matching an ignore rule is an error"
assert_contains "$(cat "$DOCTOR_TEST_TMP/state.out")" "defaults/gtk-3.0/settings.ini" "state: names the hidden defaults file"

DOCTOR_ROOT="$st_saved_root" HOME="$st_saved_home"
if [ -n "$st_saved_xdg" ]; then XDG_STATE_HOME="$st_saved_xdg"; else unset XDG_STATE_HOME; fi
# Read by the check sourced above.
# shellcheck disable=SC2034
DOCTOR_STATE_DIR=""
