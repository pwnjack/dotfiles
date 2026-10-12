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
printf '%s\n' "$(req "$FIX/iphone-weekly.ics" "$(at '2026-10-27 20:00')" one "$(changes '2026-10-27 21:00' '2026-10-27 23:30' 'Calcetto' 15m | jq -c '. + {alertChanged: true}')" | edit update | jq -r .raw)" > "$TMP/one.ics"
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
ad=$(req "$FIX/allday.ics" "$(at '2026-10-17 00:00')" all "$(changes '2026-10-18 00:00' '2026-10-20 00:00' "Mum's birthday" none true 2026-10-18 2026-10-19 | jq -c '. + {alertChanged: true}')" | edit update | raw)
assert_contains "$ad" "DTSTART;VALUE=DATE:20261018" "all-day: start date"
assert_contains "$ad" "DTEND;VALUE=DATE:20261020" "all-day: exclusive end"
assert_not_contains "$ad" "VALARM" "alert none: alarms removed"

# all-day series: one occurrence's override stays on its own day, the series keeps its start
yr=$(req "$FIX/allday-yearly.ics" "$(at '2026-01-17 00:00')" one "$(changes '2026-01-17 00:00' '2026-01-17 00:00' 'Renamed' day0 true 2026-01-17 2026-01-17)" | edit update | raw)
assert_contains "$yr" "RECURRENCE-ID;VALUE=DATE:20260117" "all-day one: override for that day"
assert_contains "$yr" "DTSTART;VALUE=DATE:20260117" "all-day one: override starts on its day"
assert_contains "$yr" "DTEND;VALUE=DATE:20260118" "all-day one: override ends the day after"
assert_contains "$yr" "SUMMARY:Renamed" "all-day one: new title"
assert_eq "$(grep -c '^DTSTART;VALUE=DATE:20200117' <<<"$yr")" 1 "all-day one: the series still starts in 2020"
assert_eq "$(req "$FIX/allday.ics" "$(at '2026-10-17 00:00')" one "$(changes '2026-10-18 00:00' '2026-10-20 00:00' 'X' none true two 2026-10-19)" | edit update | jq -r .ok)" false "all-day: a non-date day is refused"

# a malformed update fails with a reason, never a bare failure
bad=$(req "$FIX/iphone-weekly.ics" "$(at '2026-10-20 20:00')" one | edit update)
assert_json_field "$bad" '.ok' false "update: null changes refused"
assert_eq "$(jq -r '.error | length > 0' <<<"$bad")" true "update: null changes give a reason"

# moved and cross-zone overrides: the instance the card shows is the override, found by
# its own start, and it keeps its series slot (RECURRENCE-ID) for every later edit.
MOVED="$FIX/moved-override.ics"
out=$(req "$MOVED" "$(at '2026-10-13 14:00')" | edit inspect)
assert_json_field "$out" '.alert' 30m "moved inspect: reads the moved override's own alarm"
out=$(req "$MOVED" "$(at '2026-10-20 15:00')" | edit inspect)
assert_json_field "$out" '.alert' 10m "cross-zone inspect: found by its start, with its own alarm"
mv_new=$(req "$MOVED" "$(at '2026-10-13 14:00')" one "$(changes '2026-10-13 15:00' '2026-10-13 16:00' 'Standup moved' 30m)" | edit update | raw)
assert_eq "$(grep -c '^BEGIN:VEVENT' <<<"$mv_new")" 3 "moved update: no second override is added"
assert_contains "$mv_new" "RECURRENCE-ID;TZID=Europe/Rome:20261013T100000" "moved update: keeps its original slot"
assert_contains "$mv_new" "DTSTART;TZID=Europe/Rome:20261013T150000" "moved update: moves it again"
xz=$(req "$MOVED" "$(at '2026-10-20 15:00')" one "$(changes '2026-10-20 16:00' '2026-10-20 17:00' 'Standup abroad' 10m)" | edit update | raw)
assert_eq "$(grep -c '^BEGIN:VEVENT' <<<"$xz")" 3 "cross-zone update: no second override is added"
assert_contains "$xz" "DTSTART;TZID=America/New_York:20261020T100000" "cross-zone update: keeps its own zone"
assert_contains "$xz" "RECURRENCE-ID;TZID=Europe/Rome:20261020T100000" "cross-zone update: keeps its slot"
dm=$(req "$MOVED" "$(at '2026-10-13 14:00')" one | edit delete | raw)
assert_eq "$(grep -c '^BEGIN:VEVENT' <<<"$dm")" 2 "moved delete: its override goes"
assert_contains "$dm" "EXDATE;TZID=Europe/Rome:20261013T100000" "moved delete: excludes its original slot"
assert_not_contains "$dm" "EXDATE;TZID=Europe/Rome:20261013T140000" "moved delete: never excludes the new time"
dx=$(req "$MOVED" "$(at '2026-10-20 15:00')" one | edit delete | raw)
assert_eq "$(grep -c '^BEGIN:VEVENT' <<<"$dx")" 2 "cross-zone delete: its override goes"
assert_contains "$dx" "EXDATE;TZID=Europe/Rome:20261020T100000" "cross-zone delete: excludes its slot"

# alarms: a title-only edit never rewrites them, and an end-relative alarm is custom
END="$FIX/end-alarm.ics"
out=$(req "$END" "$(at '2026-10-15 19:00')" | edit inspect)
assert_json_field "$out" '.alert' custom "end-relative alarm: inspect reports custom, not a preset"
# The card sends back the alert inspect reported, so a title-only edit carries that value.
shown=$(jq -r .alert <<<"$out")
tonly=$(req "$END" "$(at '2026-10-15 19:00')" all "$(changes '2026-10-15 19:00' '2026-10-15 20:00' 'Review with Sam' "$shown")" | edit update | raw)
assert_contains "$tonly" "SUMMARY:Review with Sam" "title-only edit: the title changed"
assert_contains "$tonly" "TRIGGER;RELATED=END:-PT15M" "title-only edit: the end-relative trigger survives"
assert_contains "$tonly" "X-APPLE-DEFAULT-ALARM:TRUE" "title-only edit: Apple's alarm property survives"
assert_contains "$tonly" "X-WR-ALARMUID:B1" "title-only edit: the alarm keeps its UID"
assert_eq "$(grep -c '^BEGIN:VALARM' <<<"$tonly")" 1 "title-only edit: still one alarm"

# A title-only "All events" edit opened from a moved override keeps the series' own alarm: the
# card's alert is the override's, so the master is rewritten only when the card says the alert changed.
mt=$(req "$MOVED" "$(at '2026-10-13 14:00')" all "$(changes '2026-10-13 14:00' '2026-10-13 15:00' 'Standup renamed' 30m)" | edit update | raw)
assert_contains "$mt" "SUMMARY:Standup renamed" "all from override: the title changed"
assert_eq "$(grep -c '^TRIGGER:-PT15M' <<<"$mt")" 1 "all from override: the series keeps its -PT15M alarm"
assert_eq "$(grep -c '^TRIGGER:-PT30M' <<<"$mt")" 1 "all from override: only the override keeps -PT30M"
mc=$(req "$MOVED" "$(at '2026-10-13 14:00')" all "$(changes '2026-10-13 14:00' '2026-10-13 15:00' 'Standup renamed' 30m | jq -c '. + {alertChanged: true}')" | edit update | raw)
assert_eq "$(grep -c '^TRIGGER:-PT30M' <<<"$mc")" 2 "all from override, alert changed: the series takes the chosen alert"
# The series' times move only when the user moved them. An override's draft starts at the
# override's times, so a title, location or alert edit must leave the master's DTSTART/DTEND.
MASTER_TIMES='^DTSTART;TZID=Europe/Rome:20261006T100000$'
assert_eq "$(grep -c '^DTSTART;TZID=Europe/Rome:20261013T140000$' <<<"$mc")" 1 "all from override, no timesChanged key: counts as changed, the master takes the shown start"
mtt=$(req "$MOVED" "$(at '2026-10-13 14:00')" all "$(changes '2026-10-13 14:00' '2026-10-13 15:00' 'Standup renamed' 30m | jq -c '. + {alertChanged: true, timesChanged: false}')" | edit update | raw)
assert_eq "$(grep -c "$MASTER_TIMES" <<<"$mtt")" 1 "all from override, title/alert only: the master keeps its 10:00 start"
assert_eq "$(grep -c '^DTEND;TZID=Europe/Rome:20261006T110000$' <<<"$mtt")" 1 "all from override, title/alert only: the master keeps its 11:00 end"
assert_eq "$(grep -c '^TRIGGER:-PT30M' <<<"$mtt")" 2 "all from override, title/alert only: the master takes the alert the user chose"
mloc=$(req "$MOVED" "$(at '2026-10-13 14:00')" all "$(changes '2026-10-13 14:00' '2026-10-13 15:00' 'Standup' 15m | jq -c '. + {location: "Studio", timesChanged: false}')" | edit update | raw)
assert_contains "$mloc" "LOCATION:Studio" "all from override, location only: the location changed"
assert_eq "$(grep -c "$MASTER_TIMES" <<<"$mloc")" 1 "all from override, location only: the master keeps its 10:00 start"
ma=$(req "$MOVED" "$(at '2026-10-13 14:00')" all "$(changes '2026-10-13 14:00' '2026-10-13 15:00' 'Standup' 30m | jq -c '. + {alertChanged: true, timesChanged: false}')" | edit update | raw)
assert_eq "$(grep -c "$MASTER_TIMES" <<<"$ma")" 1 "all from override, alert only: the master keeps its 10:00 start"
# An intentional retime still moves the series, and keeps its first date (Oct 6).
mr=$(req "$MOVED" "$(at '2026-10-13 14:00')" all "$(changes '2026-10-13 15:00' '2026-10-13 16:00' 'Standup' 30m | jq -c '. + {alertChanged: true, timesChanged: true}')" | edit update | raw)
assert_contains "$mr" "DTSTART;TZID=Europe/Rome:20261006T150000" "all, retimed: the series moves to the new time"
assert_contains "$mr" "DTEND;TZID=Europe/Rome:20261006T160000" "all, retimed: the series end moves with it"
assert_not_contains "$mr" "DTSTART;TZID=Europe/Rome:20261006T100000" "all, retimed: the old series time is gone"

# A display alarm that repeats or carries a duration is not a plain preset: it is custom.
REP="$TMP/repeat-alarm.ics"
cat > "$REP" <<'EOF'
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:REPEAT-0001
DTSTAMP:20261001T080000Z
DTSTART:20261020T100000Z
DTEND:20261020T110000Z
SUMMARY:Pills
BEGIN:VALARM
ACTION:DISPLAY
DESCRIPTION:Pills
TRIGGER:-PT15M
REPEAT:2
DURATION:PT5M
END:VALARM
END:VEVENT
END:VCALENDAR
EOF
out=$(req "$REP" "$(at '2026-10-20 12:00')" | edit inspect)
assert_json_field "$out" '.alert' custom "repeating display alarm: inspect reports custom, not 15m"
assert_contains "$new" "X-WR-ALARMUID:A1" "all: a custom alarm keeps its properties"

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
assert_json_contains "$out" '.error' "changed elsewhere since you opened it" "cal.sh update: stale hash refused"
assert_eq "$(sha256sum < "$CALENDAR_DATA/home/calcetto.ics" | cut -d' ' -f1)" "$hash" "cal.sh update: file untouched when refused"
out=$(jq -cn --arg h "$hash" --arg uid "$uid" --argjson occ "$(at '2026-10-20 20:00')" \
    '{calendar: "Home", uid: $uid, occurrence: $occ, scope: "all", hash: $h, changes: null}' | bash "$TEST_DIR/cal.sh" update)
assert_json_field "$out" '.ok' false "cal.sh update: null changes refused"
assert_eq "$(jq -r '.error | length > 0' <<<"$out")" true "cal.sh update: null changes give a reason"
assert_eq "$(sha256sum < "$CALENDAR_DATA/home/calcetto.ics" | cut -d' ' -f1)" "$hash" "cal.sh update: file untouched after a malformed request"
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

# Locked writes. A sync that holds sync.lock refuses the write, and a file that changes
# between cal.sh's check and its locked recheck is refused, for update, delete and move.
export CALENDAR_LOCK_WAIT=1
lock="$CALENDAR_RUNTIME_DIR/sync.lock"
sed 's/^SUMMARY:Calcetto/SUMMARY:Phone edit/' "$FIX/iphone-weekly.ics" > "$TMP/phone.ics"
cp "$FIX/iphone-weekly.ics" "$CALENDAR_DATA/home/calcetto.ics"
hash=$(sha256sum < "$CALENDAR_DATA/home/calcetto.ics" | cut -d' ' -f1)
( exec 9>"$lock"; flock 9 && exec sleep 30 ) &
holder=$!
for ((n = 0; n < 100; n++)); do flock -n "$lock" true || break; sleep 0.05; done
out=$(upd "$hash")
assert_json_contains "$out" '.error' "A sync with iCloud is running" "locked: a write is refused while a sync holds sync.lock"
assert_eq "$(sha256sum < "$CALENDAR_DATA/home/calcetto.ics" | cut -d' ' -f1)" "$hash" "locked: the file is untouched"
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null || true

racepy="$TMP/racepy"; mkdir -p "$racepy"; export REAL_PY; REAL_PY=$(command -v python3)
cat > "$racepy/python3" <<'RACE'
#!/bin/bash
# Test seam: a phone change lands after cal.sh's check and before its locked recheck.
if [[ -n ${RACE_FILE:-} ]]; then
    cp -- "$RACE_SRC" "$RACE_FILE.new" && mv -f -- "$RACE_FILE.new" "$RACE_FILE"
fi
exec "$REAL_PY" "$@"
RACE
chmod +x "$racepy/python3"
phone=$(sha256sum < "$TMP/phone.ics" | cut -d' ' -f1)
race_home="$CALENDAR_DATA/home/calcetto.ics"
reset_home() { cp "$FIX/iphone-weekly.ics" "$race_home"; }
phone_wins() { [[ "$(sha256sum < "$race_home" | cut -d' ' -f1)" == "$phone" ]]; }
RACE_SRC="$TMP/phone.ics"; export RACE_SRC

reset_home
out=$(PATH="$racepy:$PATH" RACE_FILE="$race_home" upd "$hash")
assert_json_contains "$out" '.error' "changed elsewhere since you opened it" "race update: a file replaced before the locked recheck is refused"
assert_eq "$(phone_wins && echo yes || echo no)" yes "race update: the phone's version is left as it is"
assert_eq "$(count_ics "$CALENDAR_DATA/home")" 1 "race update: nothing new is written"

reset_home
out=$(jq -cn --arg h "$hash" --arg uid "$uid" --argjson occ "$(at '2026-10-20 20:00')" \
    '{calendar: "Home", uid: $uid, occurrence: $occ, scope: "all", hash: $h}' \
    | PATH="$racepy:$PATH" RACE_FILE="$race_home" bash "$TEST_DIR/cal.sh" delete)
assert_json_contains "$out" '.error' "changed elsewhere since you opened it" "race delete: refused, not deleted"
assert_eq "$(phone_wins && echo yes || echo no)" yes "race delete: the phone's version is kept"

reset_home
out=$(PATH="$racepy:$PATH" RACE_FILE="$race_home" upd "$hash" Work)
assert_json_contains "$out" '.error' "changed elsewhere since you opened it" "race move: refused"
assert_eq "$(phone_wins && echo yes || echo no)" yes "race move: the file stays in Home, unchanged"
assert_eq "$(count_ics "$CALENDAR_DATA/work")" 0 "race move: nothing lands in Work"
reset_home
rm -f "$race_home"

test_summary ics-edit
