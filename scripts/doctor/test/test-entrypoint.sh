# Tests for doctor.sh — sourced by run-tests.sh
#
# Sourced fragment, never executed directly, so it carries no shebang; the
# directive below tells shellcheck which shell to assume (SC2148).
# shellcheck shell=bash
#
# Variables are prefixed ep_ because every test file shares one shell.
#
# Unlike the check-module tests, these run doctor.sh as a subprocess: the
# entry point's job is process-level behaviour (exit codes, argument handling,
# bailing before checks run), which cannot be observed by sourcing it.

ep_bin="$REPO_DIR/doctor.sh"

# Entry-point fixtures describe repository state, not this runner's display
# manager. Keep the host-gated SDDM check silent in the subprocesses below.
DOCTOR_SDDM_DISPLAY_MANAGER=other
export DOCTOR_SDDM_DISPLAY_MANAGER

assert_eq "$([ -x "$ep_bin" ] && echo yes || echo no)" "yes" "doctor.sh is executable"

# --- --help ---------------------------------------------------------------
ep_help="$(bash "$ep_bin" --help 2>&1)"
assert_contains "$ep_help" "Usage" "--help prints usage"
assert_contains "$ep_help" "ERROR" "--help explains the severity levels"
assert_not_contains "$ep_help" "▸ Symlinks" "--help does not run any check"
assert_not_contains "$ep_help" "set -e" "--help omits the implementation note below the header"

bash "$ep_bin" --help >/dev/null 2>&1 && ep_rc=0 || ep_rc=$?
assert_eq "$ep_rc" "0" "--help exits 0"

bash "$ep_bin" -h >/dev/null 2>&1 && ep_rc=0 || ep_rc=$?
assert_eq "$ep_rc" "0" "-h is accepted too"

# --- unknown arguments ----------------------------------------------------
ep_bad="$(bash "$ep_bin" --nonsense 2>&1)" && ep_rc=0 || ep_rc=$?
assert_eq "$ep_rc" "2" "an unknown option exits 2"
assert_contains "$ep_bad" "nonsense" "the unknown option is named back to the user"

# --- a tree with a genuine ERROR ------------------------------------------
ep_broken="$(make_fixture)"
mkdir -p "$ep_broken/hypr"
ln -s "./nowhere-at-all" "$ep_broken/broken-link"
printf 'source = config/missing.conf\n' > "$ep_broken/hypr/hyprland.conf"
git -C "$ep_broken" add -A
git -C "$ep_broken" commit -qm "fixture"

ep_out="$(DOCTOR_ROOT="$ep_broken" DOCTOR_CACHE="$ep_broken/no-cache" bash "$ep_bin" 2>&1)" \
    && ep_rc=0 || ep_rc=$?
assert_eq "$ep_rc" "1" "a tree with errors exits 1"
assert_contains "$ep_out" "ERROR" "errors appear in the report"
assert_contains "$ep_out" "error" "the tally line is printed"
assert_contains "$ep_out" "broken-link" "the dangling symlink is reported"
assert_contains "$ep_out" "missing.conf" "the missing source target is reported"

# Every check module must have run, each printing its group heading.
assert_contains "$ep_out" "Symlinks" "the symlinks check ran"
assert_contains "$ep_out" "Config references" "the references check ran"
assert_contains "$ep_out" "Binaries" "the binaries check ran"
assert_contains "$ep_out" "Services" "the services check ran"
assert_contains "$ep_out" "Waybar" "the waybar check ran"
assert_contains "$ep_out" "Hyprctl Lua compatibility" "the hyprctl compatibility check ran"
assert_contains "$ep_out" "Hardware" "the hardware check ran"
assert_contains "$ep_out" "Typelibs and plugins" "the typelib and plugin check ran"

# --- a tree with no ERRORs ------------------------------------------------
ep_clean="$(make_fixture)"
mkdir -p "$ep_clean/wal"
printf 'colors\n' > "$ep_clean/wal/colors-hyprland.conf"
printf 'return {}\n' > "$ep_clean/wal/colors-hyprland.lua"
printf '#0e1416\n' > "$ep_clean/wal/colors"
printf 'surface=#0e1416\n' > "$ep_clean/wal/roles"
printf 'placeholder\n' > "$ep_clean/README.md"
git -C "$ep_clean" add -A
git -C "$ep_clean" commit -qm "fixture"

ep_clean_out="$(DOCTOR_ROOT="$ep_clean" DOCTOR_CACHE="$ep_clean" bash "$ep_bin" 2>&1)" \
    && ep_rc=0 || ep_rc=$?
assert_eq "$ep_rc" "0" "a tree without errors exits 0"
assert_not_contains "$ep_clean_out" "ERROR" "no errors reported for a clean tree"

# --- not a git repository -------------------------------------------------
ep_notrepo="$DOCTOR_TEST_TMP/not-a-repo"
mkdir -p "$ep_notrepo"
ep_notrepo_out="$(DOCTOR_ROOT="$ep_notrepo" bash "$ep_bin" 2>&1)" && ep_rc=0 || ep_rc=$?
assert_eq "$ep_rc" "1" "a non-repository root exits 1"
assert_contains "$ep_notrepo_out" "not a git repository" "the reason is stated plainly"
assert_not_contains "$ep_notrepo_out" "▸ Symlinks" \
    "checks are not run at all when the root is not a repository"

# --- the root is reported so the user knows what was inspected ------------
assert_contains "$ep_clean_out" "$ep_clean" "the report names the tree it checked"

# Later sourced files must see the real host unless they install their own
# stubs, so do not leak the entry-point-only seam through the shared shell.
unset DOCTOR_SDDM_DISPLAY_MANAGER
