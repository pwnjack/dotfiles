#!/bin/bash
#
# Tests for scripts/hyprland/lock.sh against the real record.sh and the
# capture fakes: hyprlock starts first and never waits for the recorder, a
# running recording is saved afterwards, and hyprlock is never started twice.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TEST_DIR/../.." && pwd)"
RECORD="$ROOT/scripts/capture/record.sh"
TMP="$(mktemp -d)"

# shellcheck source=scripts/lib/assert.sh
. "$ROOT/scripts/lib/assert.sh"

export FAKE_LOG="$TMP/log" CAPTURE_OPTIONS="$TMP/options"
export CAPTURE_STATE_DIR="$TMP/state" CAPTURE_VIDEOS="$TMP/videos"
export XDG_RUNTIME_DIR="$TMP/run"
# lock.sh finds record.sh under $XDG_CONFIG_HOME, which is this checkout.
export XDG_CONFIG_HOME="$ROOT"
export PATH="$ROOT/scripts/capture/fakes:$PATH"
mkdir -p "$FAKE_LOG" "$CAPTURE_OPTIONS" "$XDG_RUNTIME_DIR"
cleanup() {
    bash "$RECORD" stop >/dev/null 2>&1
    pkill -KILL -f "$ROOT/scripts/capture/fakes/gpu-screen-recorder" 2>/dev/null
    rm -rf "$TMP"
}
trap cleanup EXIT

reset_lock() { rm -f "$FAKE_LOG/hyprlock" "$FAKE_LOG/hyprlock.running"; }
# wait_for CMD... -- poll up to 10 s.
wait_for() {
    local i
    for ((i = 0; i < 100; i++)); do "$@" && return 0; sleep 0.1; done
    return 1
}
saved_clip() { compgen -G "$CAPTURE_VIDEOS/*.mp4" >/dev/null && [ -s "$(compgen -G "$CAPTURE_VIDEOS/*.mp4" | head -1)" ]; }
saved_toast() { grep -q 'Recording saved' "$FAKE_LOG/notify" 2>/dev/null; }
idle() { ! bash "$RECORD" status >/dev/null; }

bash "$RECORD" start region 100x100+0+0
bash "$RECORD" status >/dev/null && pass "fixture: a recording is running" || fail "fixture: a recording is running"

bash "$TEST_DIR/lock.sh"
assert_eq "$(cat "$FAKE_LOG/hyprlock")" "args=" "hyprlock starts once"
wait_for idle && pass "no recording after locking" || fail "no recording after locking"
wait_for saved_clip && pass "the recording is saved after the lock" || fail "the recording is saved after the lock"
wait_for saved_toast && pass "the saved toast is shown" || fail "the saved toast is shown"

bash "$TEST_DIR/lock.sh" --grace 30
assert_eq "$(wc -l < "$FAKE_LOG/hyprlock")" 1 "a running hyprlock is not started again"

reset_lock
bash "$TEST_DIR/lock.sh" --grace 30
assert_eq "$(cat "$FAKE_LOG/hyprlock")" "args=--grace 30" "arguments reach hyprlock"

# A recorder that ignores SIGINT must not delay the lock.
reset_lock
FAKE_GSR=hang bash "$RECORD" start region 100x100+0+0
start=$SECONDS
CAPTURE_STOP_WAIT=3 bash "$TEST_DIR/lock.sh"
[ -s "$FAKE_LOG/hyprlock" ] && [ $((SECONDS - start)) -le 1 ] \
    && pass "a recorder that hangs does not delay the lock" || fail "a recorder that hangs does not delay the lock"
wait_for idle && pass "the hung recorder is eventually killed" || fail "the hung recorder is eventually killed"

# A missing record.sh must not prevent the lock.
reset_lock
mkdir -p "$TMP/empty"
XDG_CONFIG_HOME="$TMP/empty" bash "$TEST_DIR/lock.sh"
assert_eq "$(cat "$FAKE_LOG/hyprlock")" "args=" "hyprlock starts without record.sh"

# Two concurrent callers start one hyprlock. The fake must outlive lock.sh's
# 1 s flock wait, as a real hyprlock does: with a 1 s hold the lock could come
# free while the second caller still waited, after the fake had gone.
reset_lock
export FAKE_HYPRLOCK_HOLD=3
bash "$TEST_DIR/lock.sh" & p1=$!
bash "$TEST_DIR/lock.sh" & p2=$!
wait "$p1" "$p2"
assert_eq "$(wc -l < "$FAKE_LOG/hyprlock")" 1 "concurrent locks start one hyprlock"

# A lock file that cannot be opened must not prevent the lock.
reset_lock
mkdir -p "$TMP/run2/lock.sh.lock"
XDG_RUNTIME_DIR="$TMP/run2" bash "$TEST_DIR/lock.sh"
assert_eq "$(cat "$FAKE_LOG/hyprlock")" "args=" "hyprlock starts when the lock file cannot be opened"

# A lock held elsewhere, with no hyprlock running, delays the lock by about 1 s only.
reset_lock
unset FAKE_HYPRLOCK_HOLD
flock "$XDG_RUNTIME_DIR/lock.sh.lock" sleep 3 & holder=$!
sleep 0.3
start=$EPOCHREALTIME
bash "$TEST_DIR/lock.sh"
elapsed=$(awk -v a="$start" -v b="$EPOCHREALTIME" 'BEGIN { printf "%d", (b - a) * 1000 }')
[ -s "$FAKE_LOG/hyprlock" ] && [ "$elapsed" -le 2000 ] \
    && pass "a stuck lock file does not prevent the lock" || fail "a stuck lock file does not prevent the lock"
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null

# The detached save must not inherit the lock descriptor.
reset_lock
mkdir -p "$TMP/stub/scripts/capture"
cat > "$TMP/stub/scripts/capture/record.sh" <<'STUB'
#!/bin/bash
ls /proc/$$/fd > "$FAKE_LOG/stub.fds"
STUB
chmod 755 "$TMP/stub/scripts/capture/record.sh"
XDG_CONFIG_HOME="$TMP/stub" bash "$TEST_DIR/lock.sh"
wait_for test -s "$FAKE_LOG/stub.fds" && ! grep -qx 9 "$FAKE_LOG/stub.fds" \
    && pass "the detached save does not hold the lock descriptor" || fail "the detached save does not hold the lock descriptor"

test_summary lock
