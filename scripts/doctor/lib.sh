#!/bin/bash
#
# Reporting primitives for doctor.sh checks.
#
# CONTRACT FOR CHECK MODULES:
#   Never run a check loop in a pipeline or subshell. The severity counters
#   below are plain shell variables, so `cmd | while read` increments them in
#   a subshell and every finding is silently discarded. Always write:
#       while read -r x; do ... done < <(cmd)
#   The test harness greps check modules for this pattern and fails on it.
#
#   These names are reserved by this library — check modules must not redefine
#   them: group ok err warn note summary doctor_reset doctor_q
#   doctor_require_repo _finding
#
#   Any path interpolated into a fix hint must go through doctor_q, or the hint
#   stops being copy-pasteable the moment a path contains a space.
#
#   Messages and fix hints are printed with printf %s, never echo -e, so paths,
#   grep patterns and sed commands survive verbatim (a message containing \n or
#   \t must not be rewritten). Only the colour constants get %b.
#

# Root of the dotfiles tree under test. Overridable so the test suite can point
# the checks at a throwaway fixture repo instead of the live system.
DOCTOR_ROOT="${DOCTOR_ROOT:-$HOME/.config}"

DOCTOR_RED='\033[0;31m'
DOCTOR_GREEN='\033[0;32m'
DOCTOR_YELLOW='\033[1;33m'
DOCTOR_BLUE='\033[0;34m'
DOCTOR_DIM='\033[2m'
DOCTOR_NC='\033[0m'

DOCTOR_ERRORS=0
DOCTOR_WARNINGS=0
DOCTOR_NOTICES=0

doctor_reset() {
    DOCTOR_ERRORS=0
    DOCTOR_WARNINGS=0
    DOCTOR_NOTICES=0
}

group() {
    printf '\n%b▸%b %s\n' "$DOCTOR_BLUE" "$DOCTOR_NC" "$1"
}

ok() {
    printf '  %b✓%b %s\n' "$DOCTOR_GREEN" "$DOCTOR_NC" "$1"
}

# _finding <colored-tag> <message> [fix-hint]
# Tag goes through %b so its colour escapes render; message and fix hint go
# through %s so backslashes in paths and regexes are never reinterpreted.
_finding() {
    printf '  %b  %s\n' "$1" "$2"
    if [ -n "${3:-}" ]; then
        printf '           %bfix: %s%b\n' "$DOCTOR_DIM" "$3" "$DOCTOR_NC"
    fi
}

err() {
    DOCTOR_ERRORS=$((DOCTOR_ERRORS + 1))
    _finding "${DOCTOR_RED}✗ ERROR${DOCTOR_NC}" "$1" "${2:-}"
}

warn() {
    DOCTOR_WARNINGS=$((DOCTOR_WARNINGS + 1))
    _finding "${DOCTOR_YELLOW}! WARN ${DOCTOR_NC}" "$1" "${2:-}"
}

note() {
    DOCTOR_NOTICES=$((DOCTOR_NOTICES + 1))
    _finding "${DOCTOR_DIM}· INFO ${DOCTOR_NC}" "$1" "${2:-}"
}

# doctor_q <string> — shell-quote a value for use inside a fix hint.
# A no-op for ordinary paths; escapes anything a shell would otherwise split or
# expand, so the hint can be pasted verbatim.
doctor_q() {
    printf '%q' "$1"
}

# doctor_assignment <file> <name> — print the value of one plain NAME="value"
# line. Checks read helper paths and unit names from the setup scripts this
# way instead of restating them. Nothing is printed when the name is missing or
# defined twice: a duplicate is ambiguous, and choosing one would recreate the
# second source of truth the parser exists to prevent.
doctor_assignment() {
    awk -v name="$2" '
        $0 ~ "^" name "=\"[^\"]+\"$" {
            value = $0
            sub("^[^\"]*\"", "", value)
            sub("\"$", "", value)
            count++
        }
        END { if (count == 1) print value }
    ' "$1" 2>/dev/null
}

# Guards the assumption every check makes: that DOCTOR_ROOT is a git work tree,
# since all target lists are derived from git rather than hand-written. Call it
# once from doctor.sh before running any check — individual modules must not,
# because "git returned nothing" is a normal result for most of them and only
# this function can tell that apart from "not a repository".
# Records an ERROR and returns 1 if the root is not a work tree.
doctor_require_repo() {
    if git -C "$DOCTOR_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 0
    fi
    err "$DOCTOR_ROOT is not a git repository — every check derives its targets from git" \
        "clone the dotfiles repo to $(doctor_q "$DOCTOR_ROOT"), or set DOCTOR_ROOT to where it lives"
    return 1
}

# Prints the tally. Returns 1 if any ERROR was recorded, else 0.
summary() {
    local e="$DOCTOR_ERRORS" w="$DOCTOR_WARNINGS" n="$DOCTOR_NOTICES"
    echo
    echo "$e error$([ "$e" -eq 1 ] || echo s), $w warning$([ "$w" -eq 1 ] || echo s), $n notice$([ "$n" -eq 1 ] || echo s)"
    if [ "$e" -gt 0 ]; then
        return 1
    fi
    return 0
}
