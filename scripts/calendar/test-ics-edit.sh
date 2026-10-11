#!/bin/bash
#
# Tests for scripts/calendar/ics-edit.py (directly) and cal.sh's inspect,
# update and delete (against a throwaway calendar tree, fake khal/secret-tool).
#
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"
export TZ=Europe/Rome FAKE_LOG="$TMP/log" FAKE_KEYRING="$TMP/keyring" PATH="$TEST_DIR/fakes:$PATH"
export CALENDAR_RUNTIME_DIR="$TMP/run" CALENDAR_STATE_DIR="$TMP/state" CALENDAR_OPTIONS="$TMP/options" CALENDAR_DATA="$TMP/data"
export FAKE_KHAL_LIST=/dev/null CALENDAR_NO_SYNC=1
mkdir -p "$FAKE_LOG" "$FAKE_KEYRING" "$CALENDAR_OPTIONS" "$CALENDAR_STATE_DIR"
printf 'me@example.com' > "$FAKE_KEYRING/username"
FIX="$TEST_DIR/fixtures"
at() { date -d "$1" +%s; }
count_ics() { local f=("$1"/*.ics); [[ -e ${f[0]} ]] && echo "${#f[@]}" || echo 0; }
edit() { python3 -I "$TEST_DIR/ics-edit.py" "$1"; }           # stdin: the request
req() { jq -cn --rawfile raw "$1" --argjson occ "${2:-0}" --arg scope "${3:-all}" --argjson changes "${4:-null}" \
    '{raw: $raw, account: "me@example.com", occurrence: $occ, scope: $scope, changes: $changes}'; }
raw() { jq -r .raw | tr -d '\r'; }
changes() {  # changes <start> <end> <title> <alert> [allDay startDay endDay]
    jq -cn --argjson s "$(at "$1")" --argjson e "$(at "$2")" --arg t "$3" --arg a "$4" --argjson ad "${5:-false}" \
        --arg sd "${6:-}" --arg ed "${7:-}" \
        '{title: $t, location: "Campo Rossi", allDay: $ad, start: $s, end: $e, startDay: $sd, endDay: $ed, alert: $a}'
}

# inspect
out=$(req "$FIX/iphone-weekly.ics" "$(at '2026-10-20 20:00')" | edit inspect)
assert_json_field "$out" '.alert' custom "inspect: two alarms are custom"
assert_json_field "$out" '.recurring' true "inspect: weekly repeats"
assert_json_field "$out" '.invitation' false "inspect: own event"
assert_json_field "$out" '.hash' "$(sha256sum < "$FIX/iphone-weekly.ics" | cut -d' ' -f1)" "inspect: hash of the file"
out=$(req "$FIX/iphone-invite.ics" "$(at '2026-10-15 19:00')" | edit inspect)
assert_json_field "$out" '.invitation' true "inspect: someone else's invitation"
assert_json_field "$out" '.alert' 15m "inspect: one preset alarm"
out=$(req "$FIX/allday.ics" "$(at '2026-10-17 00:00')" | edit inspect)
assert_json_field "$out" '.alert' day0 "inspect: all-day preset"
assert_json_field "$out" '.allDay' true "inspect: all-day"

# inspect: whose invitation it is, from the account's own identities
mine_principal=/aMTA2NjE3ODczMjAx/principal
mine_principal=${mine_principal,,}
own_path="$TMP/own-path.ics"; own_url="$TMP/own-url.ics"; own_email="$TMP/own-email.ics"
cp "$FIX/iphone-invite.ics" "$own_path"
sed 's|^ORGANIZER.*|ORGANIZER;CN=Me;EMAIL=me@example.com:https://p07-caldav.icloud.com:443/aMTA2NjE3ODczMjAx/principal/|' \
    "$FIX/iphone-invite.ics" > "$own_url"
sed 's|^ORGANIZER.*|ORGANIZER;CN=Me;EMAIL=ME@example.com:/somewhere/else|' "$FIX/iphone-invite.ics" > "$own_email"
own_req() { jq -cn --rawfile raw "$1" --argjson addresses "$2" --argjson occ "$(at '2026-10-15 19:00')" \
    '{raw: $raw, addresses: $addresses, occurrence: $occ, scope: "all", changes: null}'; }
out=$(own_req "$own_path" "[\"$mine_principal\"]" | edit inspect)
assert_json_field "$out" '.invitation' false "inspect: organiser is the stored principal path"
out=$(own_req "$own_url" "[\"$mine_principal\"]" | edit inspect)
assert_json_field "$out" '.invitation' false "inspect: organiser is a full CalDAV URL with a stored path"
out=$(own_req "$own_email" '["mailto:me@example.com"]' | edit inspect)
assert_json_field "$out" '.invitation' false "inspect: organiser matched only by its EMAIL parameter"
out=$(own_req "$FIX/iphone-invite.ics" '["mailto:me@example.com"]' | edit inspect)
assert_json_field "$out" '.invitation' true "inspect: another organiser's EMAIL is not one of mine"

# update, all events
new=$(req "$FIX/iphone-weekly.ics" "$(at '2026-10-20 20:00')" all "$(changes '2026-10-20 19:00' '2026-10-20 21:00' 'Calcetto' custom)" | edit update | raw)
assert_contains "$new" "DTSTART;TZID=Europe/Rome:20261013T190000" "all: first date kept, new time, same zone"
assert_contains "$new" "DTEND;TZID=Europe/Rome:20261013T210000" "all: new end"
assert_contains "$new" "RRULE:FREQ=WEEKLY;BYDAY=TU" "all: rule kept"
assert_contains "$new" "DESCRIPTION:Bring the orange bibs" "all: notes kept"
assert_contains "$new" "https://example.org/calcetto" "all: URL kept"
assert_contains "$new" "X-APPLE-TRAVEL-ADVISORY-BEHAVIOR:AUTOMATIC" "all: Apple property kept"
assert_eq "$(grep -c '^TRIGGER' <<<"$new")" 2 "all: custom alarms kept"
assert_contains "$new" "SEQUENCE:3" "all: sequence bumped"

# update, this event only (after the DST change)
printf '%s\n' "$(req "$FIX/iphone-weekly.ics" "$(at '2026-10-27 20:00')" one "$(changes '2026-10-27 21:00' '2026-10-27 23:30' 'Calcetto' 15m)" | edit update | jq -r .raw)" > "$TMP/one.ics"
one=$(tr -d '\r' < "$TMP/one.ics")
assert_eq "$(grep -c '^BEGIN:VEVENT' <<<"$one")" 2 "one: an override is added"
assert_contains "$one" "RECURRENCE-ID;TZID=Europe/Rome:20261027T200000" "one: for that date, in the series' zone"
assert_contains "$one" "DTSTART;TZID=Europe/Rome:20261027T210000" "one: its new time"
assert_eq "$(grep -c '^RRULE:FREQ=WEEKLY' <<<"$one")" 1 "one: only the series repeats"
assert_eq "$(grep -c '^TRIGGER' <<<"$one")" 3 "one: series keeps two alarms, the override has one"
assert_contains "$one" "TRIGGER:-PT15M" "one: the override's alert"
again=$(req "$TMP/one.ics" "$(at '2026-10-27 20:00')" one "$(changes '2026-10-27 21:30' '2026-10-27 23:30' 'Calcetto' 15m)" | edit update | raw)
assert_eq "$(grep -c '^BEGIN:VEVENT' <<<"$again")" 2 "one again: the same override is edited"
assert_contains "$again" "DTSTART;TZID=Europe/Rome:20261027T213000" "one again: updated"

# delete
del=$(req "$FIX/iphone-weekly.ics" "$(at '2026-10-20 20:00')" one | edit delete | raw)
assert_contains "$del" "EXDATE;TZID=Europe/Rome:20261020T200000" "delete one: an exclusion"
del=$(req "$TMP/one.ics" "$(at '2026-10-27 20:00')" one | edit delete | raw)
assert_eq "$(grep -c '^BEGIN:VEVENT' <<<"$del")" 1 "delete one: its override goes too"
assert_eq "$(req "$FIX/iphone-weekly.ics" 0 all | edit delete | jq -r .raw)" "" "delete all: nothing left"
assert_eq "$(req "$FIX/allday.ics" 0 one | edit delete | jq -r .raw)" "" "delete a one-off: nothing left"

# all-day and alerts
ad=$(req "$FIX/allday.ics" "$(at '2026-10-17 00:00')" all "$(changes '2026-10-18 00:00' '2026-10-20 00:00' "Mum's birthday" none true 2026-10-18 2026-10-19)" | edit update | raw)
assert_contains "$ad" "DTSTART;VALUE=DATE:20261018" "all-day: start date"
assert_contains "$ad" "DTEND;VALUE=DATE:20261020" "all-day: exclusive end"
assert_not_contains "$ad" "VALARM" "alert none: alarms removed"

# cal.sh: hash check, atomic write, move, delete
mkdir -p "$CALENDAR_DATA/home" "$CALENDAR_DATA/work"
echo Home > "$CALENDAR_DATA/home/displayname"; echo Work > "$CALENDAR_DATA/work/displayname"
cp "$FIX/iphone-weekly.ics" "$CALENDAR_DATA/home/calcetto.ics"
uid=6F2C1E7A-0000-4000-8000-000000000001
info=$(bash "$TEST_DIR/cal.sh" inspect Home "$uid" "$(at '2026-10-20 20:00')")
assert_json_field "$info" '.recurring' true "cal.sh inspect: finds the file by UID"
hash=$(jq -r .hash <<<"$info")
upd() { jq -cn --arg h "$1" --arg m "${2:-}" --arg uid "$uid" --argjson occ "$(at '2026-10-20 20:00')" --argjson c "$(changes '2026-10-20 19:00' '2026-10-20 21:00' 'Calcetto' custom)" \
    '{calendar: "Home", uid: $uid, occurrence: $occ, scope: "all", hash: $h, moveTo: $m, changes: $c}' | bash "$TEST_DIR/cal.sh" update; }
out=$(upd stale)
assert_json_contains "$out" '.error' "changed on your iPhone" "cal.sh update: stale hash refused"
assert_eq "$(sha256sum < "$CALENDAR_DATA/home/calcetto.ics" | cut -d' ' -f1)" "$hash" "cal.sh update: file untouched when refused"
inode=$(stat -c %i "$CALENDAR_DATA/home/calcetto.ics")
out=$(upd "$hash")
assert_json_field "$out" '.ok' true "cal.sh update: ok"
assert_contains "$(cat "$CALENDAR_DATA/home/calcetto.ics")" "T190000" "cal.sh update: written"
assert_eq "$([[ $(stat -c %i "$CALENDAR_DATA/home/calcetto.ics") != "$inode" ]] && echo new || echo same)" new "cal.sh update: a new inode"
hash=$(sha256sum < "$CALENDAR_DATA/home/calcetto.ics" | cut -d' ' -f1)
out=$(upd "$hash" Work)
assert_json_field "$out" '.ok' true "cal.sh move: ok"
assert_eq "$(count_ics "$CALENDAR_DATA/home")" 0 "cal.sh move: gone from Home"
assert_eq "$(count_ics "$CALENDAR_DATA/work")" 1 "cal.sh move: now in Work"
hash=$(sha256sum < "$CALENDAR_DATA/work/calcetto.ics" | cut -d' ' -f1)
out=$(jq -cn --arg h "$hash" --arg uid "$uid" '{calendar: "Work", uid: $uid, occurrence: 0, scope: "all", hash: $h}' | bash "$TEST_DIR/cal.sh" delete)
assert_json_field "$out" '.ok' true "cal.sh delete: ok"
assert_eq "$(count_ics "$CALENDAR_DATA/work")" 0 "cal.sh delete all: file removed"

# cal.sh inspect: the account's addresses come from writable.sh's file, or the Apple ID until it exists
cp "$own_path" "$CALENDAR_DATA/home/own.ics"
echo "$mine_principal" > "$CALENDAR_STATE_DIR/addresses"
info=$(bash "$TEST_DIR/cal.sh" inspect Home INVITE-0001 "$(at '2026-10-15 19:00')")
assert_json_field "$info" '.invitation' false "cal.sh inspect: stored addresses make it my own"
rm -f "$CALENDAR_STATE_DIR/addresses" "$CALENDAR_DATA/home/own.ics"
cp "$own_email" "$CALENDAR_DATA/home/own.ics"
info=$(bash "$TEST_DIR/cal.sh" inspect Home INVITE-0001 "$(at '2026-10-15 19:00')")
assert_json_field "$info" '.invitation' false "cal.sh inspect: without the file, the Apple ID stands in"
rm -f "$CALENDAR_DATA/home/own.ics"
cp "$FIX/iphone-invite.ics" "$CALENDAR_DATA/home/invite.ics"
info=$(bash "$TEST_DIR/cal.sh" inspect Home INVITE-0001 "$(at '2026-10-15 19:00')")
assert_json_field "$info" '.invitation' true "cal.sh inspect: Luca's invitation is not mine"
rm -f "$CALENDAR_DATA/home/invite.ics"
test_summary ics-edit
