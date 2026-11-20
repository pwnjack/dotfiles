# Tests for scripts/doctor/checks/hardware.sh — sourced by run-tests.sh
#
# Sourced fragment, never executed directly, so it carries no shebang; the
# directive below tells shellcheck which shell to assume (SC2148).
# shellcheck shell=bash
#
# The host probe is exercised for real against a fake DRM tree via
# DOCTOR_DRM_SYSFS, rather than being shadowed by a stub function. That seam
# already exists in this repo — scripts/waybar/battery.sh takes BATTERY_SYSFS
# for the same reason — and testing the real probe also covers the card-prefix
# strip, which a stub would skip entirely.
#
# Checks run ONCE, redirected to a file under $DOCTOR_TEST_TMP, and the output
# is read back. `out="$(check_hardware)"` would run the check in a subshell and
# discard its severity counters.

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/hardware.sh"

# Assigned throughout this file but read only by the check sourced above.
# DOCTOR_DRM_SYSFS is deliberately NOT exported: the check is sourced into this
# same shell and never spawned, so a plain variable reaches it, while exporting
# a fake sysfs path would hand it to every subprocess a later test file starts.
export DOCTOR_ROOT


# hw_sysfs <dir> <name:status>... — build a fake /sys/class/drm.
hw_sysfs() {
    local dir="$1"; shift
    local entry
    mkdir -p "$dir"
    for entry in "$@"; do
        mkdir -p "$dir/${entry%%:*}"
        printf '%s\n' "${entry##*:}" > "$dir/${entry%%:*}/status"
    done
}

# hw_track <root> <path> <content> — write a file and stage it, so git ls-files
# sees it. An unstaged file is invisible to the check by design.
hw_track() {
    mkdir -p "$(dirname "$1/$2")"
    printf '%s\n' "$3" > "$1/$2"
    git -C "$1" add -- "$2"
}

# hw_track_link <root> <path> <target> — stage a symlink, which git records
# with mode 120000. The target lives outside the repo, mirroring the real tree
# where every tracked symlink points into ~/.cache.
hw_track_link() {
    mkdir -p "$(dirname "$1/$2")"
    ln -sfn "$3" "$1/$2"
    git -C "$1" add -- "$2"
}

# --- the probe itself ------------------------------------------------------
# LC_ALL=C so the expected order is byte order rather than the runner's
# collation: under en_US.UTF-8 `sort` interleaves eDP-1 between DP-1 and VGA-1.
hw_drm="$DOCTOR_TEST_TMP/drm-a"
hw_sysfs "$hw_drm" "card1-DP-1:connected" "card1-HDMI-A-1:disconnected" \
                   "card0-eDP-1:connected" "card0-VGA-1:unknown"
DOCTOR_DRM_SYSFS="$hw_drm"
hw_probe="$(_hw_present_outputs | LC_ALL=C sort | tr '\n' ' ')"
assert_eq "$hw_probe" "DP-1 VGA-1 eDP-1 " \
    "probe strips the card prefix and drops only the disconnected node"

# A driver with no hotplug detect reports `unknown`, and that connector may well
# be driving a display. Counting it as absent would print a finding that is
# simply false, so it counts as present.
assert_contains "$hw_probe" "VGA-1" "an unknown-status node counts as present"

# DisplayPort MST appends one numeric component per downstream branch. The
# probe's shortest card-prefix strip already preserves that whole suffix.
hw_mst_drm="$DOCTOR_TEST_TMP/drm-mst"
hw_sysfs "$hw_mst_drm" "card1-DP-1-1:connected"
DOCTOR_DRM_SYSFS="$hw_mst_drm"
hw_mst_probe="$(_hw_present_outputs)"
assert_eq "$hw_mst_probe" "DP-1-1" "probe preserves an MST connector name whole"

# --- a fixture exercising every finding ------------------------------------
hw_fixture="$(make_fixture)"
DOCTOR_ROOT="$hw_fixture"
hw_track "$hw_fixture" "options/mainmonitor" "HDMI-A-1"
hw_track "$hw_fixture" "hypr/good.conf" "monitor=DP-1,highrr,auto,1"
hw_track "$hw_fixture" "hypr/stale.conf" '$monitor = eDP-9'
hw_track "$hw_fixture" "hypr/unknown.conf" "monitor=VGA-1,preferred,auto,1"
hw_track "$hw_fixture" "README.md" "mainmonitor  # DP-9"
hw_track "$hw_fixture" "docs/note.txt" "example uses DP-9"
hw_track "$hw_fixture" "scripts/doctor/checks/hardware.sh" "eDP|DP|HDMI-A pattern DP-9"
hw_track "$hw_fixture" "quickshell/panel/test/fixture.mjs" "{name:'DP-9'}"
hw_track "$hw_fixture" "test/test-thing.sh" "fake output HDMI-A-9"

# The symlink and the regular file carry the SAME stale name, so the pair
# isolates the mode test: only the tracked-symlink case may be skipped.
hw_cache="$DOCTOR_TEST_TMP/fake-cache"
mkdir -p "$hw_cache"
printf 'monitors = HDMI-A-9\n' > "$hw_cache/waypaper-config.ini"
hw_track_link "$hw_fixture" "waypaper/config.ini" "$hw_cache/waypaper-config.ini"
hw_track "$hw_fixture" "hypr/plain-copy.conf" "monitors = HDMI-A-9"

hw_drm2="$DOCTOR_TEST_TMP/drm-b"
hw_sysfs "$hw_drm2" "card1-DP-1:connected" "card0-VGA-1:unknown"
DOCTOR_DRM_SYSFS="$hw_drm2"

run_check check_hardware

assert_contains "$CHECK_OUT" "options/mainmonitor names HDMI-A-1" "disconnected connector is reported"
assert_contains "$CHECK_OUT" "hypr/stale.conf names eDP-9" "eDP-9 is matched whole, not as DP-9"
assert_not_contains "$CHECK_OUT" "hypr/good.conf" "a connected connector is not reported"
assert_not_contains "$CHECK_OUT" "hypr/unknown.conf" "a connector whose node reports unknown is not reported"
assert_not_contains "$CHECK_OUT" "README.md" "markdown is skipped — docs carry example names"
assert_not_contains "$CHECK_OUT" "docs/note.txt" "docs/ is skipped"
assert_not_contains "$CHECK_OUT" "scripts/doctor/checks/hardware.sh" "the doctor's own tree is skipped"
assert_not_contains "$CHECK_OUT" "quickshell/panel/test/fixture.mjs" "test fixtures are skipped — they name fake outputs"
assert_not_contains "$CHECK_OUT" "test/test-thing.sh" "the top-level test/ is skipped too"

# A tracked symlink resolves into generated cache content the user cannot
# correct by hand, so a hint naming it would misdirect. The regular file with
# identical content proves the skip keys off the mode and not the content.
assert_not_contains "$CHECK_OUT" "waypaper/config.ini" "a tracked symlink into the cache is skipped"
assert_contains "$CHECK_OUT" "hypr/plain-copy.conf names HDMI-A-9" \
    "the same content in a regular file IS reported"

assert_eq "$DOCTOR_WARNINGS" "3" "exactly three warnings"
assert_eq "$DOCTOR_ERRORS" "0" "a stale connector is never an error"

# --- MST names are whole tokens, not a plain DP parent ----------------------
hw_mst_good="$(make_fixture)"
DOCTOR_ROOT="$hw_mst_good"
hw_track "$hw_mst_good" "hypr/mst-good.conf" "monitor=DP-1-1,highrr,auto,1"
hw_mst_good_drm="$DOCTOR_TEST_TMP/drm-mst-good"
hw_sysfs "$hw_mst_good_drm" "card1-DP-1-1:connected"
DOCTOR_DRM_SYSFS="$hw_mst_good_drm"

run_check check_hardware

assert_not_contains "$CHECK_OUT" "hypr/mst-good.conf" "a present MST connector is not reported"
assert_eq "$DOCTOR_WARNINGS" "0" "a present MST connector warns about nothing"

hw_mst_stale="$(make_fixture)"
DOCTOR_ROOT="$hw_mst_stale"
hw_track "$hw_mst_stale" "hypr/mst-stale.conf" "monitor=DP-1-1,highrr,auto,1"
hw_mst_stale_drm="$DOCTOR_TEST_TMP/drm-mst-stale"
hw_sysfs "$hw_mst_stale_drm" "card1-DP-1:connected"
DOCTOR_DRM_SYSFS="$hw_mst_stale_drm"

run_check check_hardware

assert_contains "$CHECK_OUT" "hypr/mst-stale.conf names DP-1-1" \
    "a stale MST connector is reported whole"
assert_not_contains "$CHECK_OUT" "names DP-1, which" \
    "a stale MST connector is not shortened to its plain DP parent"
assert_eq "$DOCTOR_WARNINGS" "1" "a stale MST connector makes one warning"

# --- a clean tree gets the all-clear, and nothing else ----------------------
hw_clean="$(make_fixture)"
DOCTOR_ROOT="$hw_clean"
hw_track "$hw_clean" "options/mainmonitor" ""
hw_track "$hw_clean" "hypr/monitor.conf" "monitor=,highrr,auto,1"

run_check check_hardware

assert_contains "$CHECK_OUT" "no tracked config names a disconnected output" "clean tree prints ok"
assert_eq "$DOCTOR_WARNINGS" "0" "clean tree warns about nothing"

# --- no DRM nodes at all: one INFO, never a wall of warnings ----------------
hw_empty="$DOCTOR_TEST_TMP/drm-empty"
mkdir -p "$hw_empty"
DOCTOR_DRM_SYSFS="$hw_empty"
DOCTOR_ROOT="$hw_fixture"

run_check check_hardware

assert_contains "$CHECK_OUT" "no display output" "headless run explains itself"
assert_eq "$DOCTOR_WARNINGS" "0" "headless run warns about nothing"

# Files share one shell, so hand the probe back to the real machine — the same
# reason run-tests.sh resets DOCTOR_ROOT before sourcing each file. Without
# this, every later file and every subprocess it spawns inherits a fake sysfs.
# Unread within THIS file by definition — the reader is whatever is sourced
# next — which is exactly what SC2034 cannot see.
# shellcheck disable=SC2034
DOCTOR_DRM_SYSFS=/sys/class/drm
