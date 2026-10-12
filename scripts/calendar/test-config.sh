#!/bin/bash
#
# The tracked calendar configs: nothing personal in them, credentials only
# through the keyring, and khal's formats fixed to ISO (cal.sh parses them).
#
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$TEST_DIR/../.." && pwd)"
# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

vdir=$(cat "$REPO/vdirsyncer/config" 2>/dev/null)
khal=$(cat "$REPO/khal/config" 2>/dev/null)
assert_not_contains "$vdir" "@" "vdirsyncer: no e-mail address"
assert_contains "$vdir" 'username.fetch = ["command", "secret-tool", "lookup", "service", "calendar-icloud", "field", "username"]' "vdirsyncer: username from the keyring"
assert_contains "$vdir" 'password.fetch = ["command", "secret-tool", "lookup", "service", "calendar-icloud", "field", "password"]' "vdirsyncer: password from the keyring"
assert_contains "$vdir" 'collections = ["from a"]' "vdirsyncer: every iCloud calendar"
assert_contains "$vdir" 'conflict_resolution = "a wins"' "vdirsyncer: iCloud wins a conflict"
assert_contains "$vdir" 'item_types = ["VEVENT"]' "vdirsyncer: events only"
assert_contains "$khal" "dateformat = %Y-%m-%d" "khal: ISO dates"
assert_contains "$khal" "datetimeformat = %Y-%m-%d %H:%M" "khal: ISO date-times"
assert_contains "$khal" "type = discover" "khal: discovers the synced calendars"

# The doctor derives the calendar's tools from the line after this marker.
marker='# Calendar sync (scripts/calendar, docs/calendar.md)'
assert_eq "$(grep -cxF -- "    $marker" "$REPO/install.sh")" "1" "install.sh: calendar marker comment present once"
assert_eq "$(grep -xF -A1 -- "    $marker" "$REPO/install.sh" | sed -n 2p)" '    "khal" "vdirsyncer"' "install.sh: khal and vdirsyncer follow the marker"
test_summary config
