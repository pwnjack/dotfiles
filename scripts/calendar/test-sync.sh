#!/bin/bash
#
# Tests for scripts/calendar/sync.sh with fake vdirsyncer, khal, secret-tool,
# notify-send and pkill: nothing reaches iCloud, no toast appears, the real
# Waybar is never signalled.
#
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"
export TZ=Europe/Rome FAKE_LOG="$TMP/log" FAKE_KEYRING="$TMP/keyring" PATH="$TEST_DIR/fakes:$PATH"
export CALENDAR_RUNTIME_DIR="$TMP/run" CALENDAR_STATE_DIR="$TMP/state" CALENDAR_OPTIONS="$TMP/options" CALENDAR_DATA="$TMP/data"
export FAKE_KHAL_LIST="$TEST_DIR/fixtures/khal-week.json" CALENDAR_NO_SYNC=1
export CALENDAR_WRITABLE="$TEST_DIR/fakes/writable"
mkdir -p "$FAKE_LOG" "$CALENDAR_STATE_DIR" "$CALENDAR_OPTIONS"
sync_run() { bash "$TEST_DIR/sync.sh" "$@"; }
status() { cat "$CALENDAR_RUNTIME_DIR/status.json"; }
count() { [[ -f $FAKE_LOG/$1 ]] && wc -l < "$FAKE_LOG/$1" || echo 0; }

# No account.
sync_run; code=$?
assert_eq "$code" 0 "no account: exit 0"
assert_json_field "$(status)" '.state' none "no account: state none"
assert_eq "$(count vdirsyncer.argv)" 0 "no account: vdirsyncer never runs"
assert_eq "$([[ -e $CALENDAR_RUNTIME_DIR/agenda.json ]] && echo yes || echo no)" no "no account: no agenda"
assert_contains "$(cat "$FAKE_LOG/pkill")" "-RTMIN+12 waybar" "no account: Waybar signalled"

# Success, first run discovers.
mkdir -p "$FAKE_KEYRING"; printf 'me@example.com' > "$FAKE_KEYRING/username"
sync_run
assert_contains "$(cat "$FAKE_LOG/vdirsyncer.argv")" "discover icloud" "first run: discovers"
assert_contains "$(cat "$FAKE_LOG/vdirsyncer.argv")" "metasync" "success: metasync"
assert_contains "$(tail -n1 "$FAKE_LOG/vdirsyncer.argv")" "sync" "success: sync last"
assert_json_field "$(status)" '.state' ok "success: state ok"
assert_json_field "$(status)" '(.lastSuccess - now | fabs) < 5' true "success: lastSuccess is now"
assert_json_field "$(cat "$CALENDAR_RUNTIME_DIR/agenda.json")" 'length' 4 "success: agenda rendered"
assert_eq "$(count writable.argv)" 1 "first run: calendars re-classified after discover"
sync_run
assert_eq "$(grep -c discover "$FAKE_LOG/vdirsyncer.argv")" 1 "second run within 24 h: no discover"
assert_eq "$(count writable.argv)" 1 "second run within 24 h: no re-classify"
touch -d '25 hours ago' "$CALENDAR_STATE_DIR/discovered"; FAKE_WRITABLE_FAIL=1 sync_run
assert_eq "$(grep -c discover "$FAKE_LOG/vdirsyncer.argv")" 2 "after 24 h: discovers again"
assert_eq "$(count writable.argv)" 2 "after 24 h: re-classifies again"
assert_json_field "$(status)" '.state' ok "failing writable.sh: state stays ok"
touch -d "25 hours ago" "$CALENDAR_STATE_DIR/discovered"; CALENDAR_WRITABLE="$TMP/missing" sync_run
assert_json_field "$(status)" '.state' ok "missing writable.sh: state stays ok"

# Failures: classification, kept lastSuccess, one toast.
ok_at=$(jq .lastSuccess "$CALENDAR_RUNTIME_DIR/status.json")
FAKE_VDIR_ERROR='error: 401 Unauthorized' sync_run
assert_json_field "$(status)" '.state' failed "auth: failed"
assert_json_field "$(status)" '.kind' auth "auth: kind"
assert_json_field "$(status)" '.message' "Sign-in rejected" "auth: message"
assert_json_field "$(status)" '.lastSuccess' "$ok_at" "auth: lastSuccess kept"
FAKE_VDIR_ERROR='Temporary failure in name resolution' sync_run
assert_json_field "$(status)" '.kind' network "network: kind"
assert_eq "$(count notify-send)" 1 "two failures in a row: one toast"
sync_run
FAKE_VDIR_ERROR='something odd happened' sync_run
assert_json_field "$(status)" '.kind' other "other: kind"
assert_json_field "$(status)" '.message' "something odd happened" "other: the last error line"
assert_eq "$(count notify-send)" 2 "success then failure: toasts again"

sync_run
FAKE_VDIR_SILENT=1 sync_run
assert_json_field "$(status)" '.state' failed "silent failure: state failed"
assert_json_field "$(status)" '.kind' other "silent failure: kind other"
assert_json_field "$(status)" '.message' "Sync failed" "silent failure: generic message"
assert_eq "$(count notify-send)" 3 "silent failure: toast sent"
tail -n1 "$FAKE_LOG/pkill" | grep -q RTMIN+12 && ok=yes || ok=no
assert_eq "$ok" yes "silent failure: Waybar signalled"
FAKE_VDIR_ERROR=' ' sync_run
assert_json_field "$(status)" '.message' "Sync failed" "whitespace-only output: generic message"
FAKE_VDIR_ERROR=$'Syncing icloud/5ED4A843-0156-401A-B358-578AEDC71C5E\nerror: Temporary failure in name resolution' sync_run
assert_json_field "$(status)" '.kind' network "a 401 inside a collection id is not an auth failure"
FAKE_VDIR_ERROR=$'Syncing icloud/x\nerror: HTTP 401' sync_run
assert_json_field "$(status)" '.kind' auth "a 401 on an error line is an auth failure"

# Render only: no network.
before=$(count vdirsyncer.argv)
sync_run --render
assert_eq "$(count vdirsyncer.argv)" "$before" "--render: no vdirsyncer"
assert_contains "$(tail -n1 "$FAKE_LOG/pkill")" "-RTMIN+12 waybar" "--render: signals"

# Declined invitations: a successful sync writes the list and the agenda omits them.
mkdir -p "$CALENDAR_DATA/home"; echo Home > "$CALENDAR_DATA/home/displayname"
cat > "$CALENDAR_DATA/home/dentist-declined.ics" <<'EOF'
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:dentist-1
DTSTART:20261011T160000Z
DTEND:20261011T170000Z
SUMMARY:Dentist
ATTENDEE;PARTSTAT=DECLINED:mailto:me@example.com
END:VEVENT
END:VCALENDAR
EOF
rm -f "$CALENDAR_STATE_DIR/declined"
sync_run
assert_eq "$(cat "$CALENDAR_STATE_DIR/declined")" "$(printf 'Home\tdentist-1\t*')" "success: writes the declined list"
assert_json_field "$(cat "$CALENDAR_RUNTIME_DIR/agenda.json")" '[.[] | select(.uid == "dentist-1")] | length' 0 "success: agenda.json omits the declined event"
assert_json_field "$(cat "$CALENDAR_RUNTIME_DIR/agenda.json")" 'length' 3 "success: agenda.json keeps the other events"

# --render keeps an existing list (its mtime is untouched) and writes a missing one.
touch -d '2001-01-01' "$CALENDAR_STATE_DIR/declined"
sync_run --render
assert_eq "$(stat -c %Y "$CALENDAR_STATE_DIR/declined")" "$(date -d 2001-01-01 +%s)" "--render: an existing declined list is not rewritten"
rm -f "$CALENDAR_STATE_DIR/declined"; sync_run --render
assert_eq "$([[ -e $CALENDAR_STATE_DIR/declined ]] && echo yes || echo no)" yes "--render: a missing declined list is written"

# A failing scan keeps the previous list, logs one line, and leaves the sync ok.
mkdir -p "$TMP/badpy"; printf '#!/bin/sh\nexit 1\n' > "$TMP/badpy/python3"; chmod +x "$TMP/badpy/python3"
err=$(PATH="$TMP/badpy:$PATH" sync_run 2>&1 >/dev/null)
assert_eq "$(cat "$CALENDAR_STATE_DIR/declined")" "$(printf 'Home\tdentist-1\t*')" "failing scan: the previous list is kept"
assert_contains "$err" "keeping the previous list" "failing scan: one line on stderr"
assert_json_field "$(status)" '.state' ok "failing scan: the sync stays ok"

# Units.
svc=$(cat "$TEST_DIR/calendar-sync.service"); tmr=$(cat "$TEST_DIR/calendar-sync.timer")
assert_contains "$svc" "ExecStart=/usr/bin/bash %h/.config/scripts/calendar/sync.sh" "service: runs sync.sh"
assert_contains "$tmr" "OnStartupSec=2min" "timer: after login"
assert_contains "$tmr" "OnUnitActiveSec=15min" "timer: every 15 min"
test_summary sync
