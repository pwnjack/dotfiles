#!/bin/bash
#
# Tests for scripts/lib/options.sh, the one reader of options/ files.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/assert.sh"
# shellcheck source=scripts/lib/options.sh
. "$TEST_DIR/options.sh"

assert_eq "$(option "$TMP/missing")" "" "missing file: empty"
assert_eq "$(option "$TMP/missing" dflt)" "dflt" "missing file: fallback"
: > "$TMP/empty"
assert_eq "$(option "$TMP/empty" dflt)" "dflt" "empty file: fallback"
printf ' \t \n' > "$TMP/blank"
assert_eq "$(option "$TMP/blank" dflt)" "dflt" "whitespace-only: fallback"
printf '  DP-1 \t\n' > "$TMP/spaced"
assert_eq "$(option "$TMP/spaced")" "DP-1" "surrounding spaces trimmed"
printf 'paru -Syu\r\n' > "$TMP/crlf"
assert_eq "$(option "$TMP/crlf")" "paru -Syu" "CRLF: \\r trimmed, inner space kept"
printf 'first\nsecond\n' > "$TMP/multi"
assert_eq "$(option "$TMP/multi")" "first" "multi-line: first line only"
printf '\nsecond\n' > "$TMP/leading"
assert_eq "$(option "$TMP/leading" dflt)" "dflt" "empty first line: fallback"
printf 'enabled' > "$TMP/nonl"
assert_eq "$(option "$TMP/nonl")" "enabled" "no trailing newline: read"
assert_eq "$(option "$TMP")" "" "a directory: empty"

test_summary options
