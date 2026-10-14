#!/bin/bash
#
# Dotfiles test runner
# Runs the repo's test suites -- all of them, or only those covering a path.
#
# Usage: ./test.sh [--list] [--for PATH...]
#
#   (no args)      run every discovered suite
#   --for PATH...  run only the suites whose owning directory covers a PATH.
#                  Paths are repo-relative, as git and git diff report them.
#   --list         print each suite and its owning directory, run nothing
#   TEST_JOBS=N    run up to N suites at once (default: nproc; 1 = sequential)
#
# Exits 0 if every suite passed, 1 if any failed or the root is not a git
# repository, 2 on a usage error.
#
# A suite is DISCOVERED, never listed. A tracked file is a suite entry point if
# its basename is run-tests.sh, or it matches test-*.sh and its directory holds
# no run-tests.sh. The second clause is load-bearing: it keeps the doctor's
# sourced fragments out, which expect a harness around them and fail if run
# alone. A third suite in either style is covered the moment it is committed.
#
# Suites are invoked as `bash <path>`, so discovery depends on neither the exec
# bit nor shebang variance. The only contract with a suite is that it runs
# under bash and exits non-zero on failure.
#
# A suite's OWNING DIRECTORY is its own directory with a trailing test/
# component stripped, so scripts/doctor/test/run-tests.sh covers
# scripts/doctor/ and scripts/waybar/test-battery.sh covers scripts/waybar/.
# A suite directly under a top-level test/ maps to the empty prefix and so
# covers the whole tree, so it runs on EVERY commit. That is deliberate: it is
# what makes this file's own tests gate a change to this file. This mapping
# lives here and nowhere else; the pre-commit hook passes staged paths to --for
# rather than deciding for itself.
#
# Suites run concurrently, up to TEST_JOBS (default: nproc). TEST_JOBS=1 runs
# sequentially; --for uses the same pool. Suites must isolate writable state
# and stub session commands. Results stream in discovery order, with each
# suite's own duration; completion order never affects the displayed output.
# Ctrl-C terminates running suite process groups and removes captured output.
#
# Output is CAPTURED, not streamed: the doctor's suite alone emits 222 lines,
# and printing that on every commit is how a gate gets ignored. A failing
# suite's output is printed in full, so diagnosing one needs no second command.
#
# Deliberately NOT `set -e`, for the same reason doctor.sh is not: one failing
# suite must not abort the run, or the roll-up would only ever name the first.
set -uo pipefail

TEST_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default to the tree this script lives in, so a clone anywhere works without
# configuration. Overridable so this runner's own tests can point discovery at
# a fixture repo -- the same seam as DOCTOR_ROOT and BATTERY_SYSFS.
TEST_ROOT="${TEST_ROOT:-$TEST_SELF_DIR}"

TEST_GREEN='\033[0;32m'
TEST_RED='\033[0;31m'
TEST_DIM='\033[2m'
TEST_NC='\033[0m'

# Lines 3-15 are the user-facing header; everything below is an implementation
# note that does not belong in --help output.
_test_usage() {
    sed -n '3,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# _test_dir <path> -- sets TEST_DIR_OUT to the directory a path lives in, "."
# at the repo root.
#
# One definition, used by both discovery passes and by _test_owner, because
# "the directory of a path" appearing twice is a second source of truth: a
# slashless root-level path makes ${file%/*} return the FILENAME, which would
# silently stop the fragment-exclusion clause firing at the repo root.
#
# A "." sentinel rather than "": bash rejects an empty associative-array
# subscript outright, and "." can never appear as a git ls-files path.
#
# Assigns rather than prints. Printing costs a fork per tracked file per pass
# -- 470 of them on this repo, ~86ms -- and this runs on every commit once the
# pre-commit hook calls it. Inlining the case at each site would be as fast,
# but that is exactly the duplication this function exists to prevent.
_test_dir() {
    case "$1" in
        */*) TEST_DIR_OUT="${1%/*}" ;;
        *)   TEST_DIR_OUT="." ;;
    esac
}

# _test_suites -- every suite entry point, one NUL-terminated root-relative
# path per record, in git's sorted order so a run is deterministic.
#
# NUL-terminated, not newline: a tracked path may legally contain a newline,
# and splitting on one would invent two bogus suite paths out of a real file.
# That is the same reason the reads below are -d ''.
#
# Two passes over the same listing. One cannot work: a test-*.sh may be listed
# before the run-tests.sh that supersedes it, so which directories are owned
# has to be known before any entry point is emitted.
_test_suites() {
    local file dir TEST_DIR_OUT
    local -A owned=()

    # Process substitution, not a pipeline: a pipeline would fill `owned` in a
    # subshell and the second pass would see an empty map.
    while IFS= read -r -d '' file; do
        [ -f "$TEST_ROOT/$file" ] || continue
        case "${file##*/}" in
            run-tests.sh) _test_dir "$file"; owned["$TEST_DIR_OUT"]=1 ;;
        esac
    done < <(git -C "$TEST_ROOT" ls-files -z 2>/dev/null)

    while IFS= read -r -d '' file; do
        [ -f "$TEST_ROOT/$file" ] || continue
        _test_dir "$file"
        dir="$TEST_DIR_OUT"
        case "${file##*/}" in
            run-tests.sh) printf '%s\0' "$file" ;;
            test-*.sh)    [ -n "${owned[$dir]:-}" ] || printf '%s\0' "$file" ;;
        esac
    done < <(git -C "$TEST_ROOT" ls-files -z 2>/dev/null)
}

# _test_owner <suite-path> -- the path prefix a suite covers, with its trailing
# slash. Prints nothing for a suite that covers the whole tree, so that the
# prefix comparison below matches every path.
_test_owner() {
    local dir TEST_DIR_OUT
    _test_dir "$1"
    dir="$TEST_DIR_OUT"
    case "$dir" in
        .|test)  return 0 ;;
        */test)  dir="${dir%/test}" ;;
    esac
    printf '%s/' "$dir"
}

# _test_covers <owner-prefix> <path>...
# True when any path lies under the prefix. The prefix is quoted inside the
# case pattern so a glob character in a directory name stays literal.
#
# The comparison is TEXTUAL and the paths must be repo-relative. A deleted file
# still matches, which is deliberate -- the hook passes staged paths that may
# no longer exist on disk. But an ABSOLUTE path matches no owner prefix except
# the repo root's empty one, so passing one selects only the repo-root suite
# and still reports "1 suite passed": a targeted run that looks successful
# while testing nothing it was aimed at. Callers must pass what git reports.
_test_covers() {
    local owner="$1" path
    shift
    for path in "$@"; do
        case "$path" in
            "$owner"*) return 0 ;;
        esac
    done
    return 1
}

# Milliseconds since the epoch. %3N is GNU date; this repo is Arch-only.
_test_now_ms() {
    date +%s%3N
}

# _test_duration <start-ms> <end-ms> -- elapsed time as seconds to one decimal.
_test_duration() {
    local ms=$(( $2 - $1 ))
    printf '%d.%d' "$(( ms / 1000 ))" "$(( (ms % 1000) / 100 ))"
}

TEST_MODE=run
TEST_FOR=()

case "${1:-}" in
    --help|-h)
        _test_usage
        exit 0
        ;;
    --list)
        TEST_MODE=list
        ;;
    --for)
        TEST_MODE=for
        shift
        TEST_FOR=("$@")
        if [ "${#TEST_FOR[@]}" -eq 0 ]; then
            echo "test: --for needs at least one path" >&2
            echo >&2
            _test_usage >&2
            exit 2
        fi
        # Reject absolute paths rather than silently under-selecting. An
        # absolute path matches no owning prefix but the repo root's empty
        # one, so it would run only the repo-root suite and still print
        # "1 suite passed" -- a green run that tested nothing it was aimed at.
        for _test_arg in "${TEST_FOR[@]}"; do
            case "$_test_arg" in
                /*)
                    printf 'test: --for takes repo-relative paths, got %s\n' "$_test_arg" >&2
                    echo >&2
                    _test_usage >&2
                    exit 2
                    ;;
            esac
        done
        unset _test_arg
        ;;
    "")
        ;;
    *)
        echo "test: unknown option '$1'" >&2
        echo >&2
        _test_usage >&2
        exit 2
        ;;
esac

# Discovery derives from git, so without this guard "not a repository" and "no
# suites in this repo" would print the same reassuring nothing. Same reasoning
# as doctor_require_repo.
if ! git -C "$TEST_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'test: %s is not a git repository -- suites are discovered from git\n' "$TEST_ROOT" >&2
    exit 1
fi

mapfile -d '' -t TEST_SUITES < <(_test_suites)

[ "$TEST_MODE" = list ] || printf 'Testing %s\n\n' "$TEST_ROOT"

# Select once, before scheduling. Both a full run and --for use the same pool;
# --list remains a read-only discovery operation and needs no worker setup.
TEST_SELECTED=()
for _test_suite in ${TEST_SUITES[@]+"${TEST_SUITES[@]}"}; do
    _test_owner_prefix="$(_test_owner "$_test_suite")"
    if [ "$TEST_MODE" = list ]; then
        printf '%s\t%s\n' "$_test_suite" "${_test_owner_prefix:-(repo root)}"
    elif [ "$TEST_MODE" != for ] || _test_covers "$_test_owner_prefix" "${TEST_FOR[@]}"; then
        TEST_SELECTED+=("$_test_suite")
    fi
done
[ "$TEST_MODE" = list ] && exit 0

# Arch provides nproc, setsid and Bash's wait -n/-p. Validate before doing any
# work: zero jobs must not turn a selected run into a green run of no suites.
TEST_JOBS="${TEST_JOBS:-$(nproc)}"
if [[ ! $TEST_JOBS =~ ^[1-9][0-9]*$ ]]; then
    echo 'test: TEST_JOBS must be a positive integer' >&2
    exit 2
fi
TEST_RAN=${#TEST_SELECTED[@]}
# Clamp before arithmetic so even an enormous valid job count cannot overflow.
if (( ${#TEST_JOBS} > ${#TEST_RAN} )) || (( TEST_JOBS > TEST_RAN )); then
    TEST_JOBS=$(( TEST_RAN > 0 ? TEST_RAN : 1 ))
fi
TEST_FAILED=0
TEST_NEXT=0
TEST_PRINT=0
TEST_TMP="$(mktemp -d)" || exit 1
declare -A TEST_ACTIVE=()

# Each worker is its own process group. Killing only its shell would leave
# compilers, test subprocesses and background sleeps behind on Ctrl-C. Use
# TERM so suites can run cleanup traps, then kill any remaining group members.
# Also signal the PID: an interrupt can arrive before setsid creates its group.
# shellcheck disable=SC2329 # Invoked by the EXIT trap.
_test_cleanup() {
    local pid
    trap '' INT TERM
    for pid in "${!TEST_ACTIVE[@]}"; do
        kill -TERM -- "-$pid" "$pid" 2>/dev/null || true
    done
    if (( ${#TEST_ACTIVE[@]} )); then
        # Give each suite's own traps up to 3 s to remove their temporary
        # trees before anything is killed outright.
        local i alive
        for ((i = 0; i < 30; i++)); do
            alive=0
            for pid in "${!TEST_ACTIVE[@]}"; do
                kill -0 -- "-$pid" 2>/dev/null && alive=1
            done
            (( alive )) || break
            sleep 0.1
        done
        for pid in "${!TEST_ACTIVE[@]}"; do
            kill -KILL -- "-$pid" "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        done
    fi
    rm -rf "$TEST_TMP"
}
trap _test_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Workers record their own elapsed times, not the time until the parent gets
# around to printing them. Numeric filenames keep even newline-bearing suite
# paths out of the bookkeeping. A result is written only after output closes.
_test_launch() {
    local index=$1
    # shellcheck disable=SC2016 # Expanded by the worker's shell, not this one.
    setsid bash -c '
        start=$(date +%s%3N)
        bash "$1" > "$2.out" 2>&1
        rc=$?
        end=$(date +%s%3N)
        printf "%s %s %s\n" "$rc" "$start" "$end" > "$2.pending"
        mv "$2.pending" "$2.result"
    ' test-worker "$TEST_ROOT/${TEST_SELECTED[$index]}" "$TEST_TMP/$index" &
    TEST_ACTIVE[$!]=$index
}

# Reap every completed worker before refilling the pool; a slow early suite
# never prevents later completed slots being reused. wait -n is only a wakeup:
# Bash can have already reaped several jobs before it is called (then returns
# 127 without a PID), so the files and tracked PIDs, not wait -n's status, tell
# us which results to consume. This avoids both polling sleeps and lost jobs.
while (( TEST_PRINT < TEST_RAN || ${#TEST_ACTIVE[@]} )); do
    for _test_pid in "${!TEST_ACTIVE[@]}"; do
        _test_index=${TEST_ACTIVE[$_test_pid]}
        if [ -f "$TEST_TMP/$_test_index.result" ] || ! kill -0 "$_test_pid" 2>/dev/null; then
            wait "$_test_pid"
            _test_rc=$?
            # A worker killed before it could write metadata is a failure too.
            if [ ! -f "$TEST_TMP/$_test_index.result" ]; then
                _test_end="$(_test_now_ms)"
                printf '%s %s %s\n' "${_test_rc:-1}" "$_test_end" "$_test_end" > "$TEST_TMP/$_test_index.result"
                [ "$_test_rc" -ne 0 ] || printf '1 %s %s\n' "$_test_end" "$_test_end" > "$TEST_TMP/$_test_index.result"
            fi
            unset 'TEST_ACTIVE[$_test_pid]'
        fi
    done
    while (( TEST_NEXT < TEST_RAN && ${#TEST_ACTIVE[@]} < TEST_JOBS )); do
        _test_launch "$TEST_NEXT"
        TEST_NEXT=$((TEST_NEXT + 1))
    done

    # Flush only the contiguous finished prefix, always in discovery order.
    # Command substitution preserves the old treatment of trailing newlines in
    # failure output, including one indented blank line for an empty failure.
    while (( TEST_PRINT < TEST_NEXT )) && [ -f "$TEST_TMP/$TEST_PRINT.result" ]; do
        read -r _test_rc _test_start _test_end < "$TEST_TMP/$TEST_PRINT.result"
        _test_suite=${TEST_SELECTED[$TEST_PRINT]}
        if [ "$_test_rc" -eq 0 ]; then
            printf '  %b✓%b %s %b(%ss)%b\n' "$TEST_GREEN" "$TEST_NC" "$_test_suite" \
                "$TEST_DIM" "$(_test_duration "$_test_start" "$_test_end")" "$TEST_NC"
        else
            TEST_FAILED=$((TEST_FAILED + 1))
            printf '  %b✗%b %s %b(%ss)%b\n' "$TEST_RED" "$TEST_NC" "$_test_suite" \
                "$TEST_DIM" "$(_test_duration "$_test_start" "$_test_end")" "$TEST_NC"
            _test_out="$(cat "$TEST_TMP/$TEST_PRINT.out" 2>/dev/null)"
            printf '%s\n' "$_test_out" | sed 's/^/      /'
        fi
        TEST_PRINT=$((TEST_PRINT + 1))
    done
    if (( ${#TEST_ACTIVE[@]} )); then
        wait -n -p _test_finished "${!TEST_ACTIVE[@]}" 2>/dev/null || true
    fi
done

echo
if [ "$TEST_RAN" -eq 0 ]; then
    if [ "$TEST_MODE" = for ]; then
        echo "no suites cover the changed files"
    else
        echo "no test suites found"
    fi
    exit 0
fi

if [ "$TEST_FAILED" -eq 0 ]; then
    echo "$TEST_RAN suite$([ "$TEST_RAN" -eq 1 ] || echo s) passed"
    exit 0
fi

echo "$TEST_FAILED of $TEST_RAN suite$([ "$TEST_RAN" -eq 1 ] || echo s) failed"
exit 1
