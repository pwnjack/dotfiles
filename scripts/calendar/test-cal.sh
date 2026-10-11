#!/bin/bash
#
# Tests for scripts/calendar/cal.sh against a fake khal (scripts/calendar/fakes).
#
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

export TZ=Europe/Rome FAKE_LOG="$TMP/log" PATH="$TEST_DIR/fakes:$PATH"
export CALENDAR_RUNTIME_DIR="$TMP/run" CALENDAR_STATE_DIR="$TMP/state" CALENDAR_OPTIONS="$TMP/options" CALENDAR_DATA="$TMP/data"
export FAKE_KHAL_LIST="$TEST_DIR/fixtures/khal-week.json" CALENDAR_NO_SYNC=1 FAKE_KEYRING="$TMP/keyring"
mkdir -p "$FAKE_LOG" "$CALENDAR_RUNTIME_DIR" "$CALENDAR_STATE_DIR" "$CALENDAR_OPTIONS" "$CALENDAR_DATA/home-uuid" "$CALENDAR_DATA/work-uuid"
echo Home > "$CALENDAR_DATA/home-uuid/displayname"; echo '#FF9F0AFF' > "$CALENDAR_DATA/home-uuid/color"
echo Work > "$CALENDAR_DATA/work-uuid/displayname"; echo '#30B0C7FF' > "$CALENDAR_DATA/work-uuid/color"
run_cal() { bash "$TEST_DIR/cal.sh" "$@"; }

out=$(run_cal range 2026-10-11 8)
assert_json_field "$out" 'length' 4 "range: four events, the two-day one once"
assert_json_field "$out" '.[0].title' "Dentist" "range: sorted by start"
assert_json_field "$out" '.[0].startEpoch' "$(date -d '2026-10-11 18:00' +%s)" "range: local start epoch"
assert_json_field "$out" '.[0].allDay' false "range: a timed event"
assert_json_field "$out" '.[3].allDay' true "range: an all-day event"
assert_json_field "$out" '.[3].endEpoch - .[3].startEpoch' $((48 * 3600 + 3600)) "range: all-day end is the next midnight across the 25 h DST day"
assert_contains "$(tail -n1 "$FAKE_LOG/khal.argv")" "list --day-format  --json uid --json title" "range: asks khal for JSON without day headers"
assert_json_field "$out" '.[0].uid' "dentist-1" "range: keeps the UID (editing finds the file by it)"
assert_json_field "$out" '.[0].color' "#FF9F0A" "range: an 8-digit colour is cut to 6"
assert_json_field "$out" '.[0] | has("organizer")' false "range: no organizer field"
assert_json_field "$out" '[.[] | select(.recurring)] | length' 1 "range: a repeating event is marked"
assert_contains "$(tail -n1 "$FAKE_LOG/khal.argv")" "2026-10-11 8d" "range: start and length"

printf 'Work\n\n' > "$CALENDAR_OPTIONS/calendar-hidden"
run_cal range 2026-10-11 8 >/dev/null
assert_contains "$(tail -n1 "$FAKE_LOG/khal.argv")" "-d Work" "range: hidden calendars excluded"
rm "$CALENDAR_OPTIONS/calendar-hidden"

mkdir -p "$CALENDAR_DATA/promemoria-uuid"
echo Promemoria > "$CALENDAR_DATA/promemoria-uuid/displayname"; echo '#FF3B30FF' > "$CALENDAR_DATA/promemoria-uuid/color"
printf 'Promemoria\n' > "$CALENDAR_STATE_DIR/skip"
run_cal range 2026-10-11 8 >/dev/null
assert_contains "$(tail -n1 "$FAKE_LOG/khal.argv")" "-d Promemoria" "range: skipped collections excluded"

# Stale, duplicate and doubled names never reach khal; they would exit it 2.
printf 'Gone\nWork\nWork\nPromemoria\n' > "$CALENDAR_OPTIONS/calendar-hidden"
run_cal range 2026-10-11 8 >/dev/null
last=$(tail -n1 "$FAKE_LOG/khal.argv")
assert_eq "$([[ $last == *"-d Gone"* ]] && echo yes || echo no)" no "range: an unknown hidden name is not passed"
assert_eq "$(grep -o -- '-d Work' <<<"$last" | wc -l)" 1 "range: a duplicate name is passed once"
assert_eq "$(grep -o -- '-d Promemoria' <<<"$last" | wc -l)" 1 "range: a name hidden and skipped is passed once"
rm "$CALENDAR_OPTIONS/calendar-hidden"

# Every calendar excluded: khal would list them all, so it is not asked.
printf 'Home\nWork\n' > "$CALENDAR_OPTIONS/calendar-hidden"
: > "$FAKE_LOG/khal.argv"
assert_eq "$(run_cal range 2026-10-11 8)" '[]' "all excluded: range is empty"
assert_eq "$(run_cal month 2026-10)" '{"busy":[]}' "all excluded: month is empty"
assert_eq "$(run_cal year 2026)" '{"counts":[0,0,0,0,0,0,0,0,0,0,0,0]}' "all excluded: year has zero counts"
assert_eq "$(wc -c < "$FAKE_LOG/khal.argv")" 0 "all excluded: khal is never called"
rm "$CALENDAR_OPTIONS/calendar-hidden"

# A failing khal is an error, not an empty agenda.
out=$(FAKE_KHAL_LIST_FAIL=1 run_cal range 2026-10-11 8); code=$?
assert_eq "$code" 1 "khal fails: range exits 1"
assert_json_field "$out" '.ok' false "khal fails: range reports ok false"
assert_json_contains "$out" '.error' "Unknown calendar" "khal fails: range carries khal's message"
out=$(FAKE_KHAL_LIST_FAIL=1 run_cal month 2026-10); code=$?
assert_eq "$code" 1 "khal fails: month exits 1"
assert_json_field "$out" '.ok' false "khal fails: month reports ok false"
out=$(FAKE_KHAL_LIST_FAIL=1 run_cal year 2026); code=$?
assert_eq "$code" 1 "khal fails: year exits 1"

assert_json_field "$(run_cal day 2026-10-13)" 'length' 4 "day: passes the fixture through (khal does the filtering)"
assert_contains "$(tail -n1 "$FAKE_LOG/khal.argv")" "2026-10-13 1d" "day: one day"
assert_json_field "$(run_cal month 2026-10)" '.busy | join(",")' "11,13,24,25" "month: every covered day once"
assert_json_field "$(run_cal year 2026)" '.counts | length' 12 "year: twelve counts"
assert_json_field "$(run_cal year 2026)" '.counts[9]' 4 "year: October counts events by start"

# An event that starts in 2025 and runs into January counts for 2025 only.
out=$(FAKE_KHAL_LIST="$TEST_DIR/fixtures/khal-year-boundary.json" run_cal year 2026)
assert_json_field "$out" '.counts[0]' 1 "year: January counts only events starting that year"
assert_json_field "$out" '.counts[11]' 0 "year: a spill-over from last year does not hit December"

echo Work > "$CALENDAR_STATE_DIR/readonly"
cals=$(run_cal calendars)
assert_json_field "$cals" '[.[] | .name] | join(",")' "Home,Work" "calendars: names from displayname, skipped collection omitted"
assert_json_field "$cals" '.[0].color' "#FF9F0A" "calendars: colour cut to 6 digits"
assert_json_field "$cals" '.[1].color' "#30B0C7" "calendars: second colour"
assert_json_field "$cals" '.[1].writable' false "calendars: read-only list honoured"

mkdir -p "$CALENDAR_DATA/odd-uuid"
echo Odd > "$CALENDAR_DATA/odd-uuid/displayname"; echo 'not-a-colour' > "$CALENDAR_DATA/odd-uuid/color"
assert_json_field "$(run_cal calendars)" '[.[] | select(.name == "Odd")][0].color' "" "calendars: a malformed colour becomes empty"
rm -r "$CALENDAR_DATA/odd-uuid"

ics=$'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n'
req() { jq -cn --arg c "$1" --arg i "$2" '{calendar:$c, ics:$i}'; }
out=$(req Home "$ics" | run_cal add); code=$?
assert_eq "$code" 0 "add: exit 0"
assert_json_field "$out" '.ok' true "add: ok"
assert_contains "$(tail -n1 "$FAKE_LOG/khal.argv")" "import --batch -a Home" "add: batch import into the chosen calendar"
assert_eq "$(cat "$FAKE_LOG/imported.ics"; printf x)" "${ics}x" "add: the payload reaches khal unchanged"
out=$(req Work "$ics" | run_cal add); code=$?
assert_eq "$code" 1 "add: a read-only calendar is refused"
assert_json_contains "$out" '.error' "read-only" "add: says why"
out=$(req Nope "$ics" | run_cal add)
assert_json_contains "$out" '.error' "Unknown calendar" "add: an unknown calendar is refused"
out=$(req Home "hello" | run_cal add)
assert_json_contains "$out" '.error' "not a calendar event" "add: a non-VCALENDAR payload is refused"
out=$(FAKE_KHAL_IMPORT_FAIL=1 run_cal add < <(req Home "$ics"))
assert_json_contains "$out" '.error' "import failed" "add: khal's error is reported"

out=$(CAL_KHAL=khal-missing run_cal range 2026-10-11 8); code=$?
assert_eq "$code" 1 "no khal: exit 1"
assert_json_field "$out" '.error' "khal is not installed" "no khal: says so"
test_summary cal
