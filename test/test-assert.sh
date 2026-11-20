#!/bin/bash
#
# Self-test for scripts/lib/assert.sh. It lives in test/ so it runs on every
# commit: the suites that source the library only run when their own
# directory changes, so a broken assertion could otherwise pass unnoticed.
#
# Each case runs the assertion in a subshell with its own counters and checks
# whether it passed or failed, so a failing case here is the expected outcome.
#

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/assert.sh
. "$ROOT/scripts/lib/assert.sh"

# outcome <assertion> [args...] -> "pass" or "fail"
outcome() {
    (
        PASSED=0 FAILED=0
        "$@" >/dev/null
        [ "$FAILED" -eq 0 ] && [ "$PASSED" -eq 1 ] && echo pass || echo fail
    )
}

expect() {
    local expected="$1" label="$2"
    shift 2
    assert_eq "$(outcome "$@")" "$expected" "$label"
}

json='{"a":"one","b":["x","y"]}'

expect pass "assert_eq on equal values"            assert_eq same same l
expect fail "assert_eq on different values"        assert_eq same other l
expect pass "assert_contains finds a substring"    assert_contains "a-b-c" "b-" l
expect fail "assert_contains misses"               assert_contains "a-b-c" "z" l
expect pass "assert_not_contains on absence"       assert_not_contains "abc" "z" l
expect fail "assert_not_contains on presence"      assert_not_contains "abc" "b" l
expect pass "assert_json_field matches"            assert_json_field "$json" '.a' one l
expect fail "assert_json_field mismatches"         assert_json_field "$json" '.a' two l
expect pass "assert_json_contains finds"           assert_json_contains "$json" '.b | join(",")' 'x,y' l
expect fail "assert_json_contains misses"          assert_json_contains "$json" '.b | join(",")' 'z' l
expect pass "assert_json_lacks on absence"         assert_json_lacks "$json" '.a' zz l
expect fail "assert_json_lacks on presence"        assert_json_lacks "$json" '.a' on l

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
touch "$dir/file"
ln -s "$dir/missing" "$dir/dangling"
expect pass "assert_exists on a file"             assert_exists "$dir/file" l
expect pass "assert_exists on a dangling link"    assert_exists "$dir/dangling" l
expect fail "assert_exists on nothing"            assert_exists "$dir/none" l
expect pass "assert_absent on nothing"            assert_absent "$dir/none" l
expect fail "assert_absent on a file"             assert_absent "$dir/file" l
expect fail "assert_absent on a dangling link"    assert_absent "$dir/dangling" l

# after <cmd> -- the library's check, which reads the status of the command before it.
after() { "$1"; check l; }
expect pass "check after a success"               after true
expect fail "check after a failure"               after false

# wait_for returns at once on success, and gives up after its bound on failure.
export WAIT_FOR_TRIES=10
wait_for true; assert_eq "$?" 0 "wait_for returns 0 for a command that succeeds"
wait_for false; assert_eq "$?" 1 "wait_for returns 1 once its bound is spent"
(sleep 0.05; touch "$dir/later") &
wait_for test -e "$dir/later"; assert_eq "$?" 0 "wait_for sees a file that appears"
unset WAIT_FOR_TRIES

summary_status=$( (PASSED=0 FAILED=1; test_summary >/dev/null) && echo 0 || echo 1)
assert_eq "$summary_status" 1 "test_summary returns nonzero after a failure"

test_summary
