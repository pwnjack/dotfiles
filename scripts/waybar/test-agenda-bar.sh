#!/bin/bash
#
# Tests for scripts/waybar/agenda-bar.sh: the four display rules and their
# boundaries, each Bar page mode, both clocks and both locales. AGENDA_NOW
# pins the clock; CALENDAR_* point at a throwaway tree.
#
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"
export TZ=Europe/Rome CALENDAR_RUNTIME_DIR="$TMP/run" CALENDAR_OPTIONS="$TMP/options"
mkdir -p "$CALENDAR_RUNTIME_DIR" "$CALENDAR_OPTIONS"
cp "$TEST_DIR/fixtures/agenda.json" "$CALENDAR_RUNTIME_DIR/agenda.json"
icon=$'\U000F00ED'
bar() { AGENDA_NOW=$(date -d "$1" +%s) LC_TIME=${2:-it_IT.UTF-8} bash "$TEST_DIR/agenda-bar.sh"; }
mode() { printf '%s\n' "$1" > "$CALENDAR_OPTIONS/bar-agenda"; }
clock() { printf '%s\n' "$1" > "$CALENDAR_OPTIONS/clock"; }

mode soon; clock 24h
assert_json_field "$(bar '2026-10-11 16:52')" '.text' "$icon 18:00 Dentist" "soon: next timed event"
assert_json_field "$(bar '2026-10-11 16:52')" '.class' "soon" "soon: class"
assert_json_field "$(bar '2026-10-11 18:30')" '.text' "$icon now · Dentist" "in progress"
assert_json_field "$(bar '2026-10-11 18:30')" '.class' "now" "in progress: class"
assert_json_field "$(bar '2026-10-11 19:00')" '.text' "$icon 06:00 R&amp;D &lt;sync&gt;" "ended at its end second: the next one shows"
assert_not_contains "$(bar '2026-10-11 19:00')" "Dentist" "ended at its end second: Dentist is gone"
assert_json_field "$(bar '2026-10-11 18:00:00')" '.class' "now" "starts: in progress at its first second"
assert_json_field "$(bar '2026-10-11 06:00')" '.text' "$icon 18:00 Dentist" "exactly 12 h ahead: shown"
assert_json_field "$(bar '2026-10-11 05:59:59')" '.text' "$icon Mum's birthday" "12 h + 1 s ahead: not yet"
assert_json_field "$(bar '2026-10-11 19:30')" '.text' "$icon 06:00 R&amp;D &lt;sync&gt;" "tomorrow 06:00 is within 12 h, escaped"
assert_json_field "$(bar '2026-10-12 08:00')" '.text' "" "nothing soon: empty"

mode today
assert_json_field "$(bar '2026-10-11 19:30')" '.text' "$icon Mum's birthday" "today: tomorrow's event waits"
mode next
assert_json_field "$(bar '2026-10-12 08:00')" '.text' "$icon sab 17 · Weekend away with the w…" "next: a later day, Italian, truncated"
assert_json_field "$(bar '2026-10-12 08:00' en_US.UTF-8)" '.text' "$icon Sat 17 · Weekend away with the w…" "next: English"
mode soon; clock 12h
assert_json_field "$(bar '2026-10-11 16:52' en_US.UTF-8)" '.text' "$icon 06:00 PM Dentist" "12 h clock"
clock 24h
mode hidden
assert_json_field "$(bar '2026-10-11 16:52')" '.text' "" "hidden mode"
mode soon
rm "$CALENDAR_RUNTIME_DIR/agenda.json"
assert_json_field "$(bar '2026-10-11 16:52')" '.text' "" "no agenda: empty"
assert_not_contains "$(cat "$TEST_DIR/agenda-bar.sh")" "$icon" "glyph written as an escape"
test_summary agenda-bar
