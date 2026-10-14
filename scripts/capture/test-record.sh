#!/bin/bash
#
# Tests for scripts/capture/record.sh, run as a subprocess the way the strip,
# the keybind and Waybar run it. Everything it drives is a fake from
# scripts/capture/fakes/ on PATH: nothing records, no toast appears and the
# real Waybar is never signalled.
#
# Assertion helpers intentionally use condition && pass || fail throughout.
# shellcheck disable=SC2015
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECORD="$TEST_DIR/record.sh"
TMP="$(mktemp -d)"

# shellcheck disable=SC1091 # The shared assertion library has its own suite.
# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

export FAKE_LOG="$TMP/log" CAPTURE_OPTIONS="$TMP/options"
export CAPTURE_STATE_DIR="$TMP/state" CAPTURE_VIDEOS="$TMP/videos"
export FAKE_RECORD="$RECORD"
# Leave wall-clock countdowns intact, but poll and settle the fakes promptly.
export CAPTURE_TICK_WAIT=0.02 CAPTURE_COUNTDOWN_WAIT=0.02
# Margins sized for a loaded machine: ./test.sh runs nproc suites at once. The
# start wait covers the fake recorder starting Python (about 13 ms idle), and
# the stop poll keeps record.sh's stop budget (STOP_WAIT x 10 polls) at 5 s.
export CAPTURE_STOP_POLL_WAIT=0.05 CAPTURE_DISCARD_POLL_WAIT=0.01 CAPTURE_START_WAIT=0.2
export PATH="$TEST_DIR/fakes:$PATH"
BASE="-c mp4 -k h264 -ac aac -f 60 -q very_high -cursor yes"

rec() { bash "$RECORD" "$@"; }
opt() { printf '%s\n' "$2" > "$CAPTURE_OPTIONS/$1"; }
last_argv() { tail -n1 "$FAKE_LOG/gsr.argv" 2>/dev/null; }
# wait_grep <file> <text> -- up to 3 s for an asynchronous write.
wait_grep() {
    local i
    for ((i = 0; i < 300; i++)); do
        grep -qF -- "$2" "$1" 2>/dev/null && return 0
        sleep 0.01
    done
    return 1
}
# wait_ticker -- a stopped recording's ticker consumes its stop marker before
# it can report a death. Wait for that condition instead of guessing a delay,
# so exact toast-count assertions run after the relevant ticker has settled.
wait_ticker() {
    local i
    for ((i = 0; i < 300; i++)); do
        compgen -G "$CAPTURE_STATE_DIR/stopped.*" >/dev/null || return 0
        sleep 0.01
    done
    fail "a stopped recording's ticker did not settle"
    return 1
}
# reset -- stop anything left running, then empty every fixture directory.
reset() {
    local i
    rec stop >/dev/null 2>&1
    # A stop's marker is consumed by the recording's ticker on its next tick; let
    # it, or its late "Recording stopped" would land in the next test's log.
    for ((i = 0; i < 150; i++)); do
        compgen -G "$CAPTURE_STATE_DIR/stopped.*" >/dev/null || break
        sleep 0.01
    done
    unset FAKE_GSR FAKE_GSR_FINISH FAKE_SLURP CAPTURE_RECORDER FAKE_PKILL_STATUS
    rm -rf "$FAKE_LOG" "$CAPTURE_OPTIONS" "$CAPTURE_STATE_DIR" "$CAPTURE_VIDEOS"
    # A fresh log directory per test: the previous recording's ticker toasts
    # just after it consumes its stop marker, and on a loaded machine that toast
    # can land after the wait above. It inherited the old FAKE_LOG, so it writes
    # into a directory that is gone instead of this test's log.
    reset_gen=$((${reset_gen:-0} + 1))
    export FAKE_LOG="$TMP/log.$reset_gen"
    mkdir -p "$FAKE_LOG" "$CAPTURE_OPTIONS"
}
trap 'reset; rm -rf "$TMP"' EXIT
reset

# --- argument vectors: screen x audio ----------------------------------------
check_audio() { # <audio> <mic> <expected -a part, or empty> <label>
    reset
    opt capture-audio "$1"
    opt capture-mic "$2"
    rec start screen
    assert_eq "$(last_argv | sed 's/ -o .*//')" "-w TEST-1 $BASE${3:+ $3} -v no" "$4"
    rec stop >/dev/null
}
check_audio false false "" "screen, no audio: focused monitor and the fixed encoder flags"
check_audio true false "-a default_output" "desktop audio only"
check_audio false true "-a default_input" "mic only"
check_audio true true "-a default_output|default_input" "desktop audio and mic merged into one track"

reset
rec start screen
if [[ $(last_argv) =~ \ -o\ $CAPTURE_VIDEOS/Recording_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}\.mp4$ ]]; then
    pass "output is Recording_YYYY-MM-DD_HH-MM-SS.mp4 under the videos directory"
else
    fail "output name" "argv: $(last_argv)"
fi

# --- status while recording ---------------------------------------------------
status_out=$(rec status); status_rc=$?
assert_eq "$status_rc" 0 "status exits 0 while recording"
assert_contains "$status_out" "recording " "status names the phase"
assert_contains "$(rec status --json)" '"class":"recording"' "status --json carries the recording class"
assert_contains "$(cat "$CAPTURE_STATE_DIR/recording.json")" '"phase":"recording"' "state file written"
assert_contains "$(cat "$FAKE_LOG/pkill")" "-RTMIN+11 waybar" "Waybar signalled on start"

# --- start while recording stops it ---------------------------------------------
output=$(rec status | cut -d' ' -f3-)
rec start screen
[ -s "$output" ] && pass "a second start stops and saves" || fail "a second start stops and saves" "missing: $output"
[ ! -e "$CAPTURE_STATE_DIR/recording.json" ] && pass "state cleared after stop" || fail "state cleared after stop"
wait_grep "$FAKE_LOG/notify" "Recording saved" && pass "saved toast" || fail "saved toast" "$(cat "$FAKE_LOG/notify" 2>/dev/null)"
assert_contains "$(cat "$FAKE_LOG/notify")" "video-x-generic" "saved toast uses a non-symbolic icon"

# --- region and window ------------------------------------------------------------
reset
export FAKE_SLURP=800x600+10+20
rec start region
assert_eq "$(last_argv | sed 's/ -o .*//')" "-w 800x600+10+20 $BASE -v no" "region from slurp"
assert_contains "$(cat "$FAKE_LOG/slurp.argv")" "-f %wx%h+%x+%y" "slurp prints the recorder's geometry format"
rec stop >/dev/null

reset
rec start region 300x200+5+6
assert_eq "$(last_argv | sed 's/ -o .*//')" "-w 300x200+5+6 $BASE -v no" "a given region skips slurp"
[ ! -e "$FAKE_LOG/slurp.argv" ] && pass "no slurp for a given region" || fail "no slurp for a given region"
rec stop >/dev/null

reset
export FAKE_SLURP=640x480+900+40
rec start window
assert_eq "$(cat "$FAKE_LOG/slurp.stdin")" $'10,20 800x600\n900,40 640x480\n50,60 300x200' "window boxes: visible, mapped, unhidden clients, shown special workspace included"
assert_contains "$(cat "$FAKE_LOG/slurp.argv")" "-r" "window selection is restricted to the boxes"
assert_eq "$(last_argv | sed 's/ -o .*//')" "-w 640x480+900+40 $BASE -v no" "window recorded as its rectangle"
rec stop >/dev/null

# --- failures ------------------------------------------------------------------------
reset
export FAKE_GSR=die
rec start screen; rc=$?
assert_eq "$rc" 1 "early recorder death exits 1"
[ ! -e "$CAPTURE_STATE_DIR/recording.json" ] && pass "early death clears state" || fail "early death clears state"
assert_contains "$(cat "$FAKE_LOG/notify")" "Recording failed" "early death toast"
assert_contains "$(cat "$FAKE_LOG/pkill")" "-RTMIN+11 waybar" "Waybar signalled after an early failure"
assert_contains "$(cat "$FAKE_LOG/notify")" "failed to open the capture device" "toast quotes the recorder's error"

reset
export FAKE_GSR=empty
rec start screen
rec stop; rc=$?
assert_eq "$rc" 1 "an empty file is a failed stop"
assert_contains "$(cat "$FAKE_LOG/notify")" "Recording not saved" "empty file toast"

reset
export FAKE_GSR_FINISH=0.1
rec start screen
output=$(rec status | cut -d' ' -f3-)
before=$(wc -l < "$FAKE_LOG/pkill")
rec stop >/dev/null
[ "$(wc -l < "$FAKE_LOG/pkill")" -ge $((before + 2)) ] && pass "stop signals Waybar (saving, then done)" || fail "stop signals Waybar"
[ -s "$output" ] && pass "stop waits for the recorder to write the file" || fail "stop waits for the file"

reset
rec start screen
pid=$(sed -n 's/.*"pid":\([0-9]*\).*/\1/p' "$CAPTURE_STATE_DIR/recording.json")
kill -KILL "$pid"
wait_grep "$FAKE_LOG/notify" "Recording stopped" && pass "a recorder dying mid-recording is reported" \
    || fail "a recorder dying mid-recording is reported" "$(cat "$FAKE_LOG/notify" 2>/dev/null)"

reset
export FAKE_SLURP=cancel
rec start region; rc=$?
assert_eq "$rc" 0 "Esc in slurp exits 0"
[ ! -e "$FAKE_LOG/gsr.argv" ] && [ ! -e "$FAKE_LOG/notify" ] && [ ! -e "$CAPTURE_STATE_DIR/recording.json" ] \
    && pass "Esc in slurp: no recorder, no toast, no state" || fail "Esc in slurp leaves nothing behind"

reset
export CAPTURE_RECORDER=absent-recorder-qq
rec start screen; rc=$?
assert_eq "$rc" 1 "a missing recorder exits 1"
assert_contains "$(cat "$FAKE_LOG/notify")" "gpu-screen-recorder" "a missing recorder names the package"

# --- stale state ---------------------------------------------------------------------
reset
mkdir -p "$CAPTURE_STATE_DIR"
bash -c 'exit 0' & dead=$!
wait "$dead"
printf '{"pid":%s,"since":1,"started":1,"output":"x","phase":"recording"}\n' "$dead" > "$CAPTURE_STATE_DIR/recording.json"
assert_contains "$(rec status --json)" '"phase":"idle"' "a dead pid reads as idle"
[ ! -e "$CAPTURE_STATE_DIR/recording.json" ] && pass "a dead pid's state is removed" || fail "a dead pid's state is removed"
assert_contains "$(cat "$FAKE_LOG/pkill")" "-RTMIN+11 waybar" "removing a stale state signals Waybar"

# A live process under the same pid but another start time is not the recorder.
sleep 30 & other=$!
printf '{"pid":%s,"since":1,"started":1,"output":"x","phase":"recording"}\n' "$other" > "$CAPTURE_STATE_DIR/recording.json"
rec status >/dev/null; rc=$?
assert_eq "$rc" 1 "a recycled pid (wrong start time) reads as idle"
[ ! -e "$CAPTURE_STATE_DIR/recording.json" ] && pass "a recycled pid's state is removed" || fail "a recycled pid's state is removed"
printf '{"pid":%s,"since":1,"started":1,"output":"x","phase":"recording"}\n' "$other" > "$CAPTURE_STATE_DIR/recording.json"
rec stop >/dev/null
kill -0 "$other" 2>/dev/null && pass "stop never signals an unrelated process" || fail "stop killed an unrelated process"
# The same process with its true start time is alive; without "since" it is not.
read -ra pf < <(sed 's/^.*) //' "/proc/$other/stat")
printf '{"pid":%s,"since":%s,"started":1,"output":"x","phase":"recording"}\n' "$other" "${pf[19]}" > "$CAPTURE_STATE_DIR/recording.json"
rec status >/dev/null; rc=$?
assert_eq "$rc" 0 "the same pid with its real start time is alive"
printf '{"pid":%s,"started":1,"output":"x","phase":"recording"}\n' "$other" > "$CAPTURE_STATE_DIR/recording.json"
rec status >/dev/null; rc=$?
assert_eq "$rc" 1 "a state without since reads as not alive"
kill "$other"

# --- idle -----------------------------------------------------------------------------
reset
out=$(rec status --json); rc=$?
assert_eq "$rc" 0 "status --json exits 0 when idle"
assert_contains "$out" '"phase":"idle"' "idle JSON"
rec stop; rc=$?
assert_eq "$rc" 0 "stop with nothing running is a no-op"
[ ! -e "$FAKE_LOG/notify" ] && pass "no toast for a no-op stop" || fail "no toast for a no-op stop"

# --- races ---------------------------------------------------------------------------------
# A recorder killed mid-recording is reported even when Waybar's status (run on
# every signal, as the fake pkill does here) clears the state first.
reset
export FAKE_PKILL_STATUS=1
rec start screen
assert_eq "$(rec status >/dev/null; echo $?)" 0 "recording under a Waybar that runs status on every signal"
pid=$(sed -n 's/.*"pid":\([0-9]*\).*/\1/p' "$CAPTURE_STATE_DIR/recording.json")
kill -KILL "$pid"
wait_grep "$FAKE_LOG/notify" "Recording stopped" && pass "the death toast survives Waybar clearing the state" \
    || fail "the death toast survives Waybar clearing the state" "$(cat "$FAKE_LOG/notify" 2>/dev/null)"
[ ! -e "$CAPTURE_STATE_DIR/recording.json" ] && pass "state cleared after the recorder died" || fail "state cleared after the recorder died"

# Two stops at once: one save, one toast, no collision on the state file.
reset
export FAKE_GSR_FINISH=0.1
rec start screen
rec stop 2>"$TMP/stop1.err" & s1=$!
rec stop 2>"$TMP/stop2.err" & s2=$!
wait "$s1"; wait "$s2"
wait_grep "$FAKE_LOG/notify" "Recording saved"
wait_ticker
assert_eq "$(grep -c 'Recording saved' "$FAKE_LOG/notify")" 1 "two concurrent stops give exactly one saved toast"
assert_eq "$(cat "$TMP/stop1.err" "$TMP/stop2.err")" "" "concurrent stops write no errors"

# A double tap: toggle while start is still checking that the recorder lives.
reset
rec start screen & starter=$!
wait_grep "$CAPTURE_STATE_DIR/recording.json" '"phase":"recording"'
wait_grep "$FAKE_LOG/gsr.argv" '-w TEST-1'
rec toggle
wait "$starter"; rc=$?
assert_eq "$rc" 0 "the first start exits 0 after a double tap"
wait_grep "$FAKE_LOG/notify" "Recording saved"
wait_ticker
assert_eq "$(grep -c 'Recording saved' "$FAKE_LOG/notify")" 1 "a double tap saves once"
assert_not_contains "$(cat "$FAKE_LOG/notify")" "Recording failed" "a double tap is not a failure"

# Two recordings that start in one wall-clock second keep two files.
reset
mkdir -p "$CAPTURE_VIDEOS"
t=$(printf '%(%s)T' -1)
for k in 0 1 2; do
    printf -v n '%s/Recording_%(%Y-%m-%d_%H-%M-%S)T.mp4' "$CAPTURE_VIDEOS" $((t + k))
    echo keep > "$n"
done
rec start screen
if [[ $(last_argv) =~ _2\.mp4$ ]]; then pass "an existing name gets a _2 suffix"; else fail "name collision" "argv: $(last_argv)"; fi
rec stop >/dev/null
assert_eq "$(cat "$n")" keep "the earlier recording is not overwritten"

# --- countdown -------------------------------------------------------------------------
# wait_phase <phase> -- up to 3 s for status --json to report it.
wait_phase() {
    local i
    for ((i = 0; i < 300; i++)); do
        [[ $(rec status --json) == *"\"phase\":\"$1\""* ]] && return 0
        sleep 0.01
    done
    return 1
}
for ender in cancel stop toggle; do
    reset
    opt capture-delay 2
    rec start screen & starter=$!
    if wait_phase countdown; then pass "$ender: countdown phase reported"; else fail "$ender: countdown phase reported"; fi
    rec "$ender" >/dev/null
    wait "$starter"; rc=$?
    assert_eq "$rc" 0 "$ender during the countdown: start exits 0"
    [ ! -e "$FAKE_LOG/gsr.argv" ] && [ ! -e "$CAPTURE_STATE_DIR/recording.json" ] && [ ! -e "$FAKE_LOG/notify" ] \
        && pass "$ender during the countdown: nothing recorded, no state, no toast" \
        || fail "$ender during the countdown leaves nothing behind"
done

reset
opt capture-delay 2
rec start screen & starter=$!
wait_phase countdown
json=$(rec status --json)
assert_contains "$json" '"class":"countdown"' "countdown class for Waybar"
assert_contains "$json" $'\U000F051B' "countdown shows the timer glyph"
before=$(wc -l < "$FAKE_LOG/pkill")
rec cancel; wait "$starter"
[ "$(wc -l < "$FAKE_LOG/pkill")" -gt "$before" ] && pass "cancelling a countdown signals Waybar" || fail "cancel signals Waybar"

# A zero-padded delay is decimal: '08' counts down, it is not an octal error.
reset
opt capture-delay 08
rec start screen & starter=$!
if wait_phase countdown; then pass "a zero-padded delay (08) counts down"; else fail "a zero-padded delay (08) counts down"; fi
rec cancel; wait "$starter"

reset
opt capture-delay 1
rec start screen
[ -e "$FAKE_LOG/gsr.argv" ] && pass "after the countdown the recorder starts" || fail "after the countdown the recorder starts"
rec status >/dev/null && pass "recording after the countdown" || fail "recording after the countdown"
rec stop >/dev/null

reset
opt capture-delay abc
rec start screen
[ -e "$FAKE_LOG/gsr.argv" ] && pass "a non-numeric delay starts at once" || fail "a non-numeric delay starts at once"

# A cancel after the recorder was forked (the countdown's boundary) discards it.
# CAPTURE_TEST_HOLD / _LATE widen the two windows in which the flag is checked.
for hold in CAPTURE_TEST_HOLD CAPTURE_TEST_HOLD_LATE; do
    reset
    opt capture-delay 1
    export "$hold=0.5"
    bash "$RECORD" start screen & starter=$!
    wait_grep "$CAPTURE_STATE_DIR/recording.json" '"phase":"recording"'
    pid=$(sed -n 's/.*"pid":\([0-9]*\).*/\1/p' "$CAPTURE_STATE_DIR/recording.json")
    kill -TERM "$starter"
    wait "$starter"; rc=$?
    unset "$hold"
    assert_eq "$rc" 0 "$hold: a TERM after the fork exits 0"
    kill -0 "$pid" 2>/dev/null && fail "$hold: the recorder is still running" || pass "$hold: no recorder left running"
    [ -z "$(ls -A "$CAPTURE_VIDEOS" 2>/dev/null)" ] && pass "$hold: no output file left" || fail "$hold: output file left" "$(ls "$CAPTURE_VIDEOS")"
    [ ! -e "$CAPTURE_STATE_DIR/recording.json" ] && ! compgen -G "$CAPTURE_STATE_DIR/stopped.*" >/dev/null \
        && pass "$hold: no state, no stop marker" || fail "$hold: state or marker left"
    [ ! -e "$FAKE_LOG/notify" ] && pass "$hold: no toast" || fail "$hold: toast" "$(cat "$FAKE_LOG/notify")"
    assert_contains "$(tail -n1 "$FAKE_LOG/pkill")" "-RTMIN+11 waybar" "$hold: Waybar signalled"
done

# A videos directory that cannot be created after a countdown clears the countdown.
reset
opt capture-delay 1
: > "$TMP/notadir"
export CAPTURE_VIDEOS="$TMP/notadir/videos"
rec start screen; rc=$?
export CAPTURE_VIDEOS="$TMP/videos"
assert_eq "$rc" 1 "an uncreatable videos directory exits 1"
[ ! -e "$CAPTURE_STATE_DIR/recording.json" ] && pass "its countdown state is cleared" || fail "its countdown state is cleared"
assert_contains "$(cat "$FAKE_LOG/notify")" "Cannot create" "its toast names the problem"
assert_contains "$(tail -n1 "$FAKE_LOG/pkill")" "-RTMIN+11 waybar" "Waybar signalled after it"

test_summary record
