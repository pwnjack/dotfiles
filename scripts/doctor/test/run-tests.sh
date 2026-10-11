#!/bin/bash
#
# Dependency-free test harness for the doctor checks.
# Sources every test-*.sh in this directory and reports assertion results.
#
# Test files are SOURCED, not executed, so they all share one shell: call
# doctor_reset before each block and prefix any helper variables with the
# module name to avoid clobbering another file's state. Sourcing is deliberate
# — running each file in a subshell would put TESTS_PASSED in a subshell, the
# exact bug lib.sh warns about.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCTOR_DIR="$(dirname "$TEST_DIR")"
REPO_DIR="$(dirname "$(dirname "$DOCTOR_DIR")")"
export DOCTOR_DIR REPO_DIR

# Point checks at a path that does not exist, so a test file that forgets to
# override DOCTOR_ROOT fails loudly instead of inspecting the user's real
# dotfiles. Individual tests override it with a fixture from make_fixture.
DOCTOR_ROOT="$TEST_DIR/nonexistent-default"
export DOCTOR_ROOT

TESTS_PASSED=0
TESTS_FAILED=0
FILES_RUN=0

# assert_contains <haystack> <needle> <label>
assert_contains() {
    if printf '%s' "$1" | grep -qF -- "$2"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ok   $3"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL $3"
        echo "       expected to contain: $2"
        echo "       actual output:"
        printf '%s\n' "$1" | sed 's/^/         /'
    fi
}

# assert_not_contains <haystack> <needle> <label>
assert_not_contains() {
    if printf '%s' "$1" | grep -qF -- "$2"; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL $3"
        echo "       expected NOT to contain: $2"
    else
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ok   $3"
    fi
}

# assert_eq <actual> <expected> <label>
assert_eq() {
    if [ "$1" = "$2" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ok   $3"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL $3"
        echo "       expected: $2"
        echo "       actual:   $1"
    fi
}

# All fixtures live under one PID-scoped prefix so cleanup can find them by
# glob. An array registry cannot work here: callers use dir="$(make_fixture)",
# a command substitution, so any FIXTURES+=(...) inside the function would be
# recorded in a subshell and lost — the very bug lib.sh warns about. Scoping by
# $$ keeps a concurrent run's fixtures out of our sweep.
FIXTURE_PREFIX="${TMPDIR:-/tmp}/doctor-fixture.$$"

# make_fixture -> prints path to a fresh git repo in a temp dir.
# Returns non-zero rather than an empty string on failure, so a caller doing
# rm -rf "$fixture/hypr" can never expand to rm -rf /hypr.
make_fixture() {
    local dir
    dir="$(mktemp -d "$FIXTURE_PREFIX.XXXXXXXX")" || {
        echo "  FAIL could not create fixture dir"
        return 1
    }
    git -C "$dir" init -q -b main
    git -C "$dir" config user.email "test@test"
    git -C "$dir" config user.name "test"
    printf '%s' "$dir"
}

# Scratch space for test files that need to capture a check's output WITHOUT a
# command substitution: `out="$(check_x)"` runs the check in a subshell, so its
# severity counters are lost and a second run is needed to observe them. Two
# runs of a check that shells out to the system is both slow and racy, so tests
# redirect to a file here and read it back instead. Swept with the fixtures.
# Bail rather than let it be empty: a test redirecting to "$DOCTOR_TEST_TMP/x"
# would then write to /x and fail in a way that looks like a check bug.
DOCTOR_TEST_TMP="$(mktemp -d "$FIXTURE_PREFIX.scratch.XXXXXXXX")" || {
    echo "could not create scratch dir"
    exit 1
}
export DOCTOR_TEST_TMP

cleanup_fixtures() {
    local f
    # An unmatched glob stays literal, and the -d test rejects it.
    for f in "$FIXTURE_PREFIX".*; do
        [ -d "$f" ] && rm -rf "$f"
    done
}

# Always print a tally, even if a sourced test file aborts the shell (an
# unbound variable under set -u would otherwise kill the run silently).
# RUN_COMPLETE, not FILES_RUN -eq FILES_TOTAL, is what proves the run finished:
# an abort inside the LAST file leaves those counts equal and would otherwise
# report a green "0 failures". exit 1 from the trap overrides the exit status.
RUN_COMPLETE=0
report() {
    echo
    echo "$FILES_RUN files, $((TESTS_PASSED + TESTS_FAILED)) assertions, $TESTS_FAILED failures"
    if [ "$RUN_COMPLETE" -ne 1 ]; then
        echo "ABORTED after $FILES_RUN of $FILES_TOTAL files — tally above is incomplete"
        exit 1
    fi
}
trap 'cleanup_fixtures; report' EXIT

FILES_TOTAL=0
for test_file in "$TEST_DIR"/test-*.sh; do
    [ -e "$test_file" ] || continue
    FILES_TOTAL=$((FILES_TOTAL + 1))
done

# Mechanical guard for the subshell contract documented in lib.sh: no check
# module may run a loop in a pipeline.
echo "▸ contract"
if grep -rnE '\|[[:space:]]*while[[:space:]]' "$DOCTOR_DIR"/checks/*.sh 2>/dev/null; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL pipeline-into-while above: findings would be lost in a subshell"
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ok   no pipeline-into-while in check modules"
fi

for test_file in "$TEST_DIR"/test-*.sh; do
    [ -e "$test_file" ] || continue
    FILES_RUN=$((FILES_RUN + 1))
    echo "▸ $(basename "$test_file")"
    # Every file starts from the same safe default. Files are sourced into one
    # shell in glob order, so without this a file that forgets to override
    # DOCTOR_ROOT silently inherits the previous file's fixture — and a file
    # that saves/restores it would save that stale value, not the default.
    DOCTOR_ROOT="$TEST_DIR/nonexistent-default"
    # shellcheck source=/dev/null
    source "$test_file"
done
RUN_COMPLETE=1

[ "$TESTS_FAILED" -eq 0 ] || exit 1
exit 0
