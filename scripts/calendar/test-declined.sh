#!/bin/bash
#
# Tests for scripts/calendar/declined.py: the fixture calendar (fixtures/declined)
# and small trees built here for the matching rules. Reads only; no network.
#
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"
export TZ=Europe/Rome
FIX="$TEST_DIR/fixtures/declined"
scan() { python3 -I "$TEST_DIR/declined.py" "$@"; }

# The fixture calendar, one rule per line (calendar, UID, key), sorted:
#   one-off and daily invitations declined as a whole ("*");
#   a declined override under an accepted series, keyed by its own DTSTART;
#   an accepted override under a declined series ("!"); a moved override;
#   the DST-boundary overrides (UTC and another TZID) on 2026-10-25.
# Accepted, pending, declined-by-someone-else, own and garbage stay out.
printf '/aMTA2NjE3ODczMjAx/principal\nmailto:me@example.com\n' > "$TMP/addresses"
expected_fixtures=$(printf '%s\n' \
    "Home	DECLINED-DAILY	*" \
    "Home	DECLINED-IPHONE	*" \
    "Home	DST-TZID-OVERRIDE	2026-10-25 11:00" \
    "Home	DST-UTC-OVERRIDE	2026-10-25 11:00" \
    "Home	MOVED-OVERRIDE	2026-10-12 14:00" \
    "Home	SERIES-DECLINED-MASTER	!2026-10-19 10:00" \
    "Home	SERIES-DECLINED-MASTER	*" \
    "Home	SERIES-OVERRIDE-DECLINED	2026-10-12 10:00")
out=$(scan "$FIX" "$TMP/addresses" me@example.com); code=$?
assert_eq "$code" 0 "fixtures: exit 0"
assert_eq "$out" "$expected_fixtures" "fixtures: exact rule lines, named Home"

# The moved override hides 14:00 only: no rule names its RECURRENCE-ID slot (10:00).
assert_eq "$(grep -c 'MOVED-OVERRIDE	2026-10-12 10:00' <<<"$out")" 0 "moved override: no rule for its old RECURRENCE-ID slot"
assert_eq "$(grep -c 'MOVED-OVERRIDE	2026-10-12 14:00' <<<"$out")" 1 "moved override: the rule sits at its DTSTART"

# Malformed overrides never fall back to RECURRENCE-ID: a missing DTSTART emits no rule
# (not even for the old slot), and a non-date DTSTART drops its whole file, master's "*"
# included. The valid files beside them still print: the exact list above proves that.
assert_eq "$(grep -c 'OVERRIDE-NO-DTSTART' <<<"$out")" 0 "missing DTSTART: no rule for its RECURRENCE-ID slot"
assert_eq "$(grep -c 'OVERRIDE-BAD-DTSTART' <<<"$out")" 0 "non-date DTSTART: its file contributes no rules at all"

# Without an addresses file the Apple ID stands for mailto:.
out=$(scan "$FIX" "$TMP/missing" me@example.com)
assert_eq "$(grep -c 'DECLINED-DAILY	\*' <<<"$out")" 1 "no addresses file: the Apple ID fallback matches the daily invitation"
out=$(scan "$FIX" "$TMP/missing" "")
assert_eq "$out" "" "no addresses file, no Apple ID: the account has no identity, so nothing is declined"

# Small trees for the matching rules.
tree="$TMP/tree"; work="$tree/work"; mkdir -p "$work"; echo Work > "$work/displayname"
cat > "$work/url-principal.ics" <<'EOF'
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:URL-PRINCIPAL
DTSTART:20261020T170000Z
DTEND:20261020T180000Z
ATTENDEE;PARTSTAT=DECLINED:https://caldav.icloud.com/1369483447/principal/
END:VEVENT
END:VCALENDAR
EOF
cat > "$work/mailto-only.ics" <<'EOF'
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:MAILTO-ONLY
DTSTART:20261021T170000Z
DTEND:20261021T180000Z
ATTENDEE;PARTSTAT=declined:mailto:ME@example.com
END:VEVENT
END:VCALENDAR
EOF
cat > "$work/allday-override.ics" <<'EOF'
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:ALLDAY-OVERRIDE
DTSTART;VALUE=DATE:20261013
DTEND;VALUE=DATE:20261014
RRULE:FREQ=DAILY;COUNT=3
ATTENDEE;PARTSTAT=ACCEPTED:mailto:me@example.com
END:VEVENT
BEGIN:VEVENT
UID:ALLDAY-OVERRIDE
RECURRENCE-ID;VALUE=DATE:20261013
DTSTART;VALUE=DATE:20261014
DTEND;VALUE=DATE:20261015
ATTENDEE;PARTSTAT=DECLINED:mailto:me@example.com
END:VEVENT
END:VCALENDAR
EOF
printf 'this is not an event\n' > "$work/garbage.ics"

# The principal path given as a full https URL matches the file's normalised path.
printf '/1369483447/principal\n' > "$TMP/principal-only"
out=$(scan "$tree" "$TMP/principal-only" "")
assert_eq "$out" "$(printf 'Work\tURL-PRINCIPAL\t*')" "principal URL matches the normalised path in the addresses file"

# A non-empty addresses file replaces the Apple ID fallback, so mailto-only stays visible.
out=$(scan "$tree" "$TMP/principal-only" me@example.com)
assert_eq "$out" "$(printf 'Work\tURL-PRINCIPAL\t*')" "non-empty addresses file: no Apple ID fallback"

# An empty addresses file falls back to the Apple ID, compared case-insensitively.
: > "$TMP/empty"
out=$(scan "$tree" "$TMP/empty" ME@Example.com)
assert_eq "$out" "$(printf 'Work\tALLDAY-OVERRIDE\t2026-10-14\nWork\tMAILTO-ONLY\t*')" "empty addresses file: Apple ID fallback, case-insensitive; PARTSTAT is case-insensitive; an all-day override is keyed by its date"

# A missing data tree is an empty list, not an error.
out=$(scan "$TMP/no-such-dir" "$TMP/addresses" me@example.com); code=$?
assert_eq "$code" 0 "missing data dir: exit 0"
assert_eq "$out" "" "missing data dir: no output"

# An unreadable folder is skipped; the rest of the scan still runs.
if [[ $(id -u) != 0 ]]; then
    locked="$tree/locked"; mkdir -p "$locked"; echo Locked > "$locked/displayname"
    cp "$FIX/home/iphone-declined.ics" "$locked/"; chmod 000 "$locked"
    out=$(scan "$tree" "$TMP/principal-only" ""); code=$?
    chmod 700 "$locked"
    assert_eq "$code" 0 "unreadable folder: exit 0"
    assert_eq "$(grep -c 'DECLINED-IPHONE' <<<"$out")" 0 "unreadable folder: its events are skipped"
    assert_eq "$(grep -c 'URL-PRINCIPAL' <<<"$out")" 1 "unreadable folder: the other folders are still scanned"
fi
test_summary declined
