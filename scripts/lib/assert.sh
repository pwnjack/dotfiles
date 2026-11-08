#!/bin/bash
#
# Assertions shared by the standalone test suites. Sourced, never executed.
#
# Each suite sources this, calls the assertions, and ends with
# `test_summary [name]`, whose status is the suite's exit status. The doctor's
# harness (scripts/doctor/test/run-tests.sh) keeps its own: its modules are
# sourced into one shell and share its counters and reserved names.
#
# test/test-assert.sh exercises this file on every commit, since suites under
# other directories only run when their own directory changes.
#

PASSED=0
FAILED=0

pass() {
    PASSED=$((PASSED + 1))
    echo "  ok   $1"
}

# fail <label> [detail...] -- each detail is printed on its own indented line.
fail() {
    FAILED=$((FAILED + 1))
    echo "  FAIL $1"
    shift
    [ $# -eq 0 ] || printf '       %s\n' "$@"
}

# assert_eq <actual> <expected> <label>
assert_eq() {
    if [ "$1" = "$2" ]; then
        pass "$3"
    else
        fail "$3" "expected: $2" "actual:   $1"
    fi
}

# assert_contains <text> <needle> <label>
assert_contains() {
    if printf '%s' "$1" | grep -qF -- "$2"; then
        pass "$3"
    else
        fail "$3" "expected to contain: $2" "actual:" "$1"
    fi
}

# assert_not_contains <text> <needle> <label>
assert_not_contains() {
    if printf '%s' "$1" | grep -qF -- "$2"; then
        fail "$3" "expected NOT to contain: $2" "actual:" "$1"
    else
        pass "$3"
    fi
}

# assert_json_field <json> <jq-filter> <expected> <label>
assert_json_field() {
    local actual
    actual=$(printf '%s' "$1" | jq -r "$2" 2>/dev/null)
    if [ "$actual" = "$3" ]; then
        pass "$4"
    else
        fail "$4" "filter:   $2" "expected: $3" "actual:   $actual" "json:     $1"
    fi
}

# assert_json_contains <json> <jq-filter> <needle> <label>
assert_json_contains() {
    local actual
    actual=$(printf '%s' "$1" | jq -r "$2" 2>/dev/null)
    if printf '%s' "$actual" | grep -qF -- "$3"; then
        pass "$4"
    else
        fail "$4" "filter: $2" "expected to contain: $3" "actual: $actual"
    fi
}

# assert_json_lacks <json> <jq-filter> <needle> <label>
assert_json_lacks() {
    local actual
    actual=$(printf '%s' "$1" | jq -r "$2" 2>/dev/null)
    if printf '%s' "$actual" | grep -qF -- "$3"; then
        fail "$4" "filter: $2" "expected NOT to contain: $3" "actual: $actual"
    else
        pass "$4"
    fi
}

# check <label> -- pass or fail by the exit status of the command just before it:
#     grep -q needle "$out"
#     check "the needle is rendered"
check() {
    local rc=$?
    if [ "$rc" -eq 0 ]; then pass "$1"; else fail "$1" "exit status $rc"; fi
}

# test_summary [name] -- prints the tally; returns nonzero when anything failed.
test_summary() {
    echo
    echo "  ${1:+$1: }$PASSED passed, $FAILED failed"
    [ "$FAILED" -eq 0 ]
}
