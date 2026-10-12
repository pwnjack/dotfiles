# Tests for scripts/doctor/checks/calendar.sh — sourced by run-tests.sh
#
# Sourced fragment, never executed directly, so it carries no shebang.
# shellcheck shell=bash

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/calendar.sh"

cal_root="$DOCTOR_TEST_TMP/cal-root"
mkdir -p "$cal_root/scripts/calendar"
touch "$cal_root/scripts/calendar/calendar-sync.timer"
# Fixture installer: the marker line and the package line after it. The real
# install.sh is only asserted against in the real-tree block below.
cat > "$cal_root/install.sh" <<'EOT'
PACKAGES=(
    "pavucontrol" "blueman"
    # Calendar sync (scripts/calendar, docs/calendar.md)
    "khal" "vdirsyncer"
    # Headset battery, for scripts/devices/devices.sh
    "headsetcontrol"
)
EOT
cal_account=me
cal_enabled=yes
cal_tools="khal vdirsyncer"
cal_status='{"state":"ok","kind":"","message":"","lastSuccess":1000,"lastAttempt":1000}'
cal_now=1100

_cal_account() { printf '%s' "$cal_account"; }
_cal_timer_enabled() { [ "$cal_enabled" = yes ]; }
_cal_have() { case " $cal_tools " in *" $1 "*) return 0 ;; esac; return 1; }
_cal_status() { printf '%s' "$cal_status"; }
_cal_now() { printf '%s' "$cal_now"; }

cal_run() {
    doctor_reset
    DOCTOR_ROOT="${1:-$cal_root}" check_calendar > "$DOCTOR_TEST_TMP/cal.out" 2>&1
    cal_out=$(cat "$DOCTOR_TEST_TMP/cal.out")
}
cal_healthy() {
    cal_account=me; cal_enabled=yes; cal_tools="khal vdirsyncer"
    cal_status='{"state":"ok","kind":"","message":"","lastSuccess":1000,"lastAttempt":1000}'
    cal_now=1100
}

mkdir -p "$DOCTOR_TEST_TMP/cal-bare"
cal_run "$DOCTOR_TEST_TMP/cal-bare"
assert_eq "$cal_out" "" "calendar: a tree without the timer prints nothing"

cal_healthy; cal_account=""; cal_run
assert_eq "$cal_out" "" "calendar: no account prints nothing"

cal_healthy; cal_run
assert_contains "$cal_out" "iCloud calendar syncing" "calendar: healthy is ok"
assert_eq "$DOCTOR_WARNINGS$DOCTOR_ERRORS" "00" "calendar: healthy has no findings"

cal_healthy; cal_tools="khal"; cal_run
assert_contains "$cal_out" "vdirsyncer is not installed" "calendar: missing vdirsyncer is reported"
assert_contains "$cal_out" "sudo pacman -S --needed khal vdirsyncer" "calendar: install hint is derived from install.sh"
assert_eq "$DOCTOR_ERRORS" 1 "calendar: a missing tool is one error"

cal_healthy; cal_enabled=no; cal_run
assert_contains "$cal_out" "calendar-sync.timer is not enabled" "calendar: timer off is reported"
assert_contains "$cal_out" "scripts/calendar/setup.sh" "calendar: setup hint"
assert_eq "$DOCTOR_WARNINGS" 1 "calendar: timer off is one warning"

cal_healthy
cal_status='{"state":"failed","kind":"auth","message":"Sign-in rejected","lastSuccess":1000,"lastAttempt":1090}'; cal_run
assert_contains "$cal_out" "last sync failed: Sign-in rejected" "calendar: failure reported"
assert_contains "$cal_out" "scripts/calendar/sync.sh" "calendar: failure hint runs the sync"

cal_healthy
cal_now=$((1000 + 3601)); cal_run
assert_contains "$cal_out" "no successful sync in the last hour" "calendar: stale reported"
cal_healthy
cal_status='{"state":"none","kind":"","message":"","lastSuccess":null,"lastAttempt":1000}'; cal_run
assert_contains "$cal_out" "no successful sync in the last hour" "calendar: a null lastSuccess is stale"

# No status yet (missing file, or an empty one): an account without any sync
# on record is a warning, never the all-clear.
cal_healthy
cal_status=""; cal_run
assert_contains "$cal_out" "no sync status yet" "calendar: a missing status is reported"
assert_contains "$cal_out" "scripts/calendar/sync.sh" "calendar: no-status hint runs the sync"
assert_not_contains "$cal_out" "iCloud calendar syncing" "calendar: a missing status is not ok"
assert_eq "$DOCTOR_WARNINGS" 1 "calendar: a missing status is one warning"
cal_status=$'  \n'; cal_run
assert_contains "$cal_out" "no sync status yet" "calendar: an empty status is reported"
assert_not_contains "$cal_out" "iCloud calendar syncing" "calendar: an empty status is not ok"
cal_healthy

# Unvalidated fields must never reach shell arithmetic, and the shell must
# survive the call: the harness runs under set -u, where a bad operand aborts.
cal_healthy
cal_reached=no
cal_status='{"state":"ok","kind":"","message":"","lastSuccess":"oops","lastAttempt":1000}'; cal_run
cal_reached=yes
assert_eq "$cal_reached" yes "calendar: a string lastSuccess does not abort the shell"
assert_contains "$cal_out" "status.json is not valid" "calendar: a string lastSuccess is reported invalid"
assert_contains "$cal_out" "scripts/calendar/sync.sh" "calendar: invalid status hint runs the sync"
assert_not_contains "$cal_out" "iCloud calendar syncing" "calendar: an invalid status is not ok"

cal_reached=no
cal_status='{"state":"ok",'; cal_run
cal_reached=yes
assert_eq "$cal_reached" yes "calendar: invalid JSON does not abort the shell"
assert_contains "$cal_out" "status.json is not valid" "calendar: invalid JSON is reported invalid"
assert_eq "$DOCTOR_WARNINGS" 1 "calendar: invalid JSON is one warning"
cal_healthy

# A message is free text: a unit separator or a newline in it must neither shift
# lastSuccess into the message's place nor end the field early.
cal_reached=no
cal_status='{"state":"failed","kind":"auth","message":"hello\u001foops\nafter","lastSuccess":1000,"lastAttempt":1090}'; cal_run
cal_reached=yes
assert_eq "$cal_reached" yes "calendar: a message with U+001F and a newline does not abort the shell"
assert_contains "$cal_out" "last sync failed: hello oops after" "calendar: control characters in a message become spaces"
assert_eq "$DOCTOR_WARNINGS" 1 "calendar: a failed message with control characters is one warning"

# A newline in the message of a fresh sync must not be read as a stale one.
cal_healthy; cal_reached=no
cal_status='{"state":"ok","kind":"","message":"hello\nworld","lastSuccess":1090,"lastAttempt":1090}'; cal_run
cal_reached=yes
assert_eq "$cal_reached" yes "calendar: a message with a newline does not abort the shell"
assert_not_contains "$cal_out" "no successful sync" "calendar: a newline in a fresh message is not stale"
assert_contains "$cal_out" "iCloud calendar syncing" "calendar: a fresh sync with a multi-line message is ok"
cal_healthy

# install.sh without the marker: the tools cannot be derived, so say so, but
# the timer and status checks still run.
mkdir -p "$DOCTOR_TEST_TMP/cal-nomark/scripts/calendar"
touch "$DOCTOR_TEST_TMP/cal-nomark/scripts/calendar/calendar-sync.timer"
printf 'PACKAGES=(\n    "khal" "vdirsyncer"\n)\n' > "$DOCTOR_TEST_TMP/cal-nomark/install.sh"
cal_healthy; cal_enabled=no; cal_run "$DOCTOR_TEST_TMP/cal-nomark"
assert_contains "$cal_out" "cannot derive the calendar tools from install.sh" "calendar: a missing marker is reported"
assert_contains "$cal_out" "git -C" "calendar: the underivable hint points at install.sh"
assert_contains "$cal_out" "calendar-sync.timer is not enabled" "calendar: timer check still runs without the tools"
assert_eq "$DOCTOR_WARNINGS" 2 "calendar: underivable tools and timer are two warnings"
cal_healthy

# The real tree: the parse must keep working against what is tracked.
assert_eq "$(_cal_tools "$REPO_DIR/install.sh")" "khal vdirsyncer" \
    "calendar: the real install.sh yields khal and vdirsyncer"
