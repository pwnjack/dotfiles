#!/bin/bash
#
# Tests for scripts/calendar/setup.sh and writable.sh with a file-backed fake
# keyring, fake curl/vdirsyncer/systemctl: no account is touched, nothing is
# enabled, and no secret may ever reach argv.
#
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"
export TZ=Europe/Rome FAKE_LOG="$TMP/log" FAKE_KEYRING="$TMP/keyring" PATH="$TEST_DIR/fakes:$PATH"
export CALENDAR_RUNTIME_DIR="$TMP/run" CALENDAR_STATE_DIR="$TMP/state" CALENDAR_OPTIONS="$TMP/options" CALENDAR_DATA="$TMP/data"
export FAKE_KHAL_LIST="$TEST_DIR/fixtures/khal-week.json" CALENDAR_NO_SYNC=1 CALENDAR_VDIR_STATUS="$TMP/vstatus"
mkdir -p "$FAKE_LOG" "$CALENDAR_OPTIONS"
setup() { bash "$TEST_DIR/setup.sh" "$@"; }
secret='s3cr-etpw-xxxx-yyyy'

out=$(setup 2>&1); code=$?
assert_eq "$code" 0 "install path, no account: exit 0"
assert_contains "$out" "Settings › Calendar" "install path: points at the panel"
assert_eq "$([[ -e $FAKE_LOG/systemctl.argv ]] && echo yes || echo no)" no "install path, no account: no units touched"

out=$(printf 'me@example.com\n%s\n' "$secret" | FAKE_VDIR_ERROR='401 Unauthorized' setup --sign-in --stdin 2>&1); code=$?
assert_eq "$code" 1 "sign-in rejected: exit 1"
assert_contains "$out" "Sign-in rejected" "sign-in rejected: says so"
assert_eq "$([[ -e $FAKE_KEYRING/password ]] && echo yes || echo no)" no "sign-in rejected: password cleared"
assert_eq "$([[ -e $FAKE_KEYRING/username ]] && echo yes || echo no)" no "sign-in rejected: username cleared"

out=$(printf 'me@example.com\n%s\n' "$secret" | FAKE_SECRET_FAIL_FIELD=password setup --sign-in --stdin 2>&1); code=$?
assert_eq "$code" 1 "keyring rejects the password: exit 1"
assert_contains "$out" "Could not store the account in the keyring" "keyring rejects the password: says so"
assert_eq "$([[ -e $FAKE_KEYRING/username || -e $FAKE_KEYRING/password ]] && echo yes || echo no)" no "keyring rejects the password: nothing left behind"

out=$(printf 'me@example.com\n%s\n' "$secret" | setup --sign-in --stdin 2>&1); code=$?
assert_eq "$code" 0 "sign-in: exit 0"
assert_eq "$(cat "$FAKE_KEYRING/username")" "me@example.com" "sign-in: username stored"
assert_eq "$(cat "$FAKE_KEYRING/password")" "$secret" "sign-in: password stored"
assert_eq "$(cat "$CALENDAR_STATE_DIR/readonly")" "Family" "sign-in: read-only calendars recorded"
assert_eq "$(cat "$CALENDAR_STATE_DIR/skip")" "Reminders" "sign-in: reminder lists skipped"
assert_eq "$(cat "$CALENDAR_STATE_DIR/addresses")" "$(printf '%s\n' /123456/principal /abcdef/principal urn:uuid:123456 mailto:me@example.com mailto:me@example.com)" "sign-in: addresses normalised to paths"
assert_contains "$(cat "$FAKE_LOG/curl.stdin")" "creds-on-stdin" "writable: credentials on stdin"
assert_contains "$(cat "$FAKE_LOG/systemctl.argv")" "--user link" "sign-in: units linked"
assert_contains "$(cat "$FAKE_LOG/systemctl.argv")" "--user enable --now calendar-sync.timer" "sign-in: timer enabled"
logs=$(cat "$FAKE_LOG"/*.argv)
assert_not_contains "$logs" "$secret" "no secret in any argv"

# A failing request leaves the previous classification untouched.
printf 'Family\n' > "$CALENDAR_STATE_DIR/readonly"; printf 'Reminders\n' > "$CALENDAR_STATE_DIR/skip"; printf '/old\n' > "$CALENDAR_STATE_DIR/addresses"
FAKE_CURL_FAIL=/calendars/ bash "$TEST_DIR/writable.sh" 2>/dev/null; code=$?
assert_eq "$([[ $code -ne 0 ]] && echo failed || echo ok)" failed "writable: a failing request exits non-zero"
assert_eq "$(cat "$CALENDAR_STATE_DIR/addresses")" "/old" "writable: failure leaves addresses unchanged"
assert_eq "$(cat "$CALENDAR_STATE_DIR/readonly")" "Family" "writable: failure leaves readonly unchanged"
assert_eq "$(find "$CALENDAR_STATE_DIR" -name '*.*' | wc -l)" 0 "writable: failure leaves no temp files"

before=$(wc -l < "$FAKE_LOG/systemctl.argv")
setup >/dev/null 2>&1
new=$(tail -n +"$((before + 1))" "$FAKE_LOG/systemctl.argv")
assert_contains "$new" "--user link" "install path with an account: links the units"
assert_contains "$new" "enable --now calendar-sync.timer" "install path with an account: enables the timer"

mkdir -p "$CALENDAR_DATA/x" "$CALENDAR_RUNTIME_DIR"; echo '[]' > "$CALENDAR_RUNTIME_DIR/agenda.json"
out=$(FAKE_SECRET_CLEAR_NOOP=1 setup --sign-out 2>&1); code=$?
assert_eq "$code" 1 "sign-out, keyring keeps the account: exit 1"
assert_contains "$out" "Could not remove the account from the keyring" "sign-out, keyring keeps the account: says so"
assert_eq "$([[ -e $CALENDAR_DATA ]] && echo yes || echo no)" no "sign-out, keyring keeps the account: local copy still removed"

setup --sign-out; code=$?
assert_eq "$code" 0 "sign-out: exit 0"
assert_eq "$(find "$FAKE_KEYRING" -type f | wc -l)" 0 "sign-out: keyring cleared"
assert_contains "$(cat "$FAKE_LOG/systemctl.argv")" "--user disable --now calendar-sync.timer" "sign-out: timer disabled"
assert_eq "$([[ -e $CALENDAR_DATA ]] && echo yes || echo no)" no "sign-out: local copy removed"
assert_eq "$([[ -e $CALENDAR_STATE_DIR ]] && echo yes || echo no)" no "sign-out: state dir removed"
assert_eq "$([[ -e $CALENDAR_RUNTIME_DIR/agenda.json ]] && echo yes || echo no)" no "sign-out: agenda removed"
assert_contains "$(tail -n1 "$FAKE_LOG/pkill")" "-RTMIN+12 waybar" "sign-out: Waybar signalled"
test_summary setup
