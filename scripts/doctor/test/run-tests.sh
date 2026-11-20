#!/bin/bash
#
# Dependency-free test harness for the doctor checks.
# Sources every test-*.sh in this directory and reports assertion results.
#
# Test files are SOURCED, not executed, so they all share one shell: call
# doctor_reset before each block and prefix any helper variables with the
# module name to avoid clobbering another file's state. Sourcing is deliberate
# — running each file in a subshell would put PASSED in a subshell, the
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

# shellcheck source=scripts/lib/assert.sh
. "$REPO_DIR/scripts/lib/assert.sh"
FILES_RUN=0

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

# commit_fixture <dir> — commit everything in a fixture repo.
commit_fixture() { git -C "$1" add -A && git -C "$1" commit -qm fixture; }

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

# run_check <check_fn> — run once in this shell, so the counters survive; the
# output lands in $CHECK_OUT and $DOCTOR_TEST_TMP/check.out.
# shellcheck disable=SC2034  # read by the sourced test files
run_check() { doctor_reset; "$1" > "$DOCTOR_TEST_TMP/check.out" 2>&1; CHECK_OUT="$(<"$DOCTOR_TEST_TMP/check.out")"; }

# finding_line <file> <substring> -> the first matching line, or empty. Assert
# severity on the finding's own line, never against the whole report.
finding_line() { grep -F -- "$2" "$1" 2>/dev/null | head -n1; }

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
    echo "$FILES_RUN files, $((PASSED + FAILED)) assertions, $FAILED failures"
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
    fail "pipeline-into-while above: findings would be lost in a subshell"
else
    pass "no pipeline-into-while in check modules"
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

[ "$FAILED" -eq 0 ] || exit 1
exit 0
