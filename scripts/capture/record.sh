#!/bin/bash
#
# Screen recording, and the only thing that talks to gpu-screen-recorder.
# The capture strip, Super+Shift+R, Waybar's custom/recording and lock.sh all
# come through here, so a recording has exactly one owner.
#
# Usage:
#   record.sh start [screen|window|region [WxH+X+Y]]
#   record.sh stop               stop and save (also cancels a countdown)
#   record.sh cancel             cancel a countdown; a running recording is left alone
#   record.sh toggle [target]
#   record.sh status [--json]    exit 0 while counting down or recording
#
# The target defaults to options/capture-rec-target. Delay, desktop audio and
# mic come from options/capture-delay, capture-audio and capture-mic: the
# strip writes them and this script reads them, so the keybind and the strip
# can never record differently.
#
# State: $XDG_RUNTIME_DIR/capture/recording.json (/run/user/UID/capture if unset, never /tmp), one line,
#   {"pid":…,"since":…,"started":…,"output":"…","phase":"countdown|recording|stopping"}
# For a countdown, pid is this script and started is when recording begins;
# otherwise pid is the recorder and started is when it began. A process is
# identified by pid AND "since", its start time (field 22 of /proc/PID/stat):
# a pid that is gone, a zombie, or now belongs to another process, means "not
# recording", and read_state removes the file and signals Waybar, so a crash
# never leaves the bar showing a timer. A state without "since" is not alive.
#
# stop takes $state_dir/stop.lock, so concurrent stops (keybind, lock, bar
# click) run one after another; the second finds nothing left to do. stop
# leaves $state_dir/stopped.<pid>.<since> for the ticker, which toasts "Recording
# stopped" for a recorder that died without one, however the state was read.
#
# Waybar's module runs once and on signal 11. This script sends that signal on
# every change and, through a ticker child, once a second while recording, so
# an idle bar runs nothing at all.
#
# gpu-screen-recorder installs its own SIGINT handler, which is what lets
# `kill -INT` finalise the file even though a background job of a
# non-interactive shell starts with SIGINT ignored. A bash stand-in cannot
# undo that ignore, so the test's fake recorder is Python.
#
set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
options_dir="${CAPTURE_OPTIONS:-$config_dir/options}"
state_dir="${CAPTURE_STATE_DIR:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/capture}"
videos="${CAPTURE_VIDEOS:-$HOME/Videos/Recordings}"
recorder="${CAPTURE_RECORDER:-gpu-screen-recorder}"
stop_wait="${CAPTURE_STOP_WAIT:-10}"
# Timing seams for subprocess tests; production intervals stay unchanged.
ticker_wait="${CAPTURE_TICK_WAIT:-1}"
countdown_wait="${CAPTURE_COUNTDOWN_WAIT:-1}"
stop_poll_wait="${CAPTURE_STOP_POLL_WAIT:-0.1}"
discard_poll_wait="${CAPTURE_DISCARD_POLL_WAIT:-0.1}"
start_wait="${CAPTURE_START_WAIT:-0.5}"
state="$state_dir/recording.json"
log="$state_dir/gsr.log"
# KMS capture needs this helper to hold cap_sys_admin; doctor's binaries check
# reads the name from this line.
# shellcheck disable=SC2034
readonly KMS_SERVER=gsr-kms-server

# Nerd Font glyphs, escaped so no editor can drop them: timer, record dot.
glyph_timer=$'\U000F051B' glyph_rec=$'\U000F044A'

usage() {
    echo 'usage: record.sh start [screen|window|region [WxH+X+Y]] | stop | cancel | toggle [target] | status [--json]' >&2
    exit 2
}

# option <name> <default> -> the first line of options/<name>, or the default.
option() {
    local value=""
    { read -r value < "$options_dir/$1"; } 2>/dev/null
    printf '%s' "${value:-$2}"
}

signal_bar() { pkill -RTMIN+11 waybar 2>/dev/null || true; }
notify() { notify-send -a Capture -i "$1" "$2" "${3-}" 2>/dev/null || true; }
now() { printf '%(%s)T' -1; }

# proc_stat <pid> -> sets proc_state and proc_since (field 22 of /proc/PID/stat).
# Fields are counted from the text after the LAST ") ", so a comm containing
# spaces or parentheses cannot shift them. Builtins only: no forks.
proc_stat() {
    local stat rest
    local -a f
    proc_state="" proc_since=""
    [ -n "${1-}" ] && [ -r "/proc/$1/stat" ] || return 1
    { read -r stat < "/proc/$1/stat"; } 2>/dev/null || return 1
    [[ $stat == *') '* ]] || return 1
    rest=${stat##*) }
    read -ra f <<< "$rest"
    proc_state=${f[0]-} proc_since=${f[19]-}
    [ -n "$proc_since" ]
}

# alive <pid> <since> -> 0 when that very process (not a recycled pid) still
# runs and is not a zombie.
alive() {
    [ -n "${2-}" ] && proc_stat "$1" && [ "$proc_state" != Z ] && [ "$proc_since" = "$2" ]
}

# read_state -> sets pid since started output phase; 1, removing the file and
# signalling Waybar, when nothing is live.
read_state() {
    local line=""
    pid="" since="" started="" output="" phase=""
    { read -r line < "$state"; } 2>/dev/null
    [ -n "$line" ] || return 1
    [[ $line =~ \"pid\":([0-9]+) ]] && pid=${BASH_REMATCH[1]}
    [[ $line =~ \"since\":([0-9]+) ]] && since=${BASH_REMATCH[1]}
    [[ $line =~ \"started\":([0-9]+) ]] && started=${BASH_REMATCH[1]}
    [[ $line =~ \"output\":\"([^\"]*)\" ]] && output=${BASH_REMATCH[1]}
    [[ $line =~ \"phase\":\"([a-z]+)\" ]] && phase=${BASH_REMATCH[1]}
    if ! alive "$pid" "$since"; then
        rm -f "$state"
        signal_bar
        return 1
    fi
}

# write_state <pid> <phase> <output> <started> <since>
write_state() {
    local out=${3//\\/\\\\}
    out=${out//\"/\\\"}
    mkdir -p "$state_dir" || return 1
    printf '{"pid":%s,"since":%s,"started":%s,"output":"%s","phase":"%s"}\n' "$1" "$5" "$4" "$out" "$2" > "$state.tmp.$$" \
        && mv -f "$state.tmp.$$" "$state"
}

# fmt <seconds> -> m:ss, or h:mm:ss from an hour on (model.mjs formatElapsed agrees).
fmt() {
    local s=$1
    if (( s >= 3600 )); then
        printf '%d:%02d:%02d' $((s / 3600)) $((s % 3600 / 60)) $((s % 60))
    else
        printf '%d:%02d' $((s / 60)) $((s % 60))
    fi
}

first_error() {
    local line
    line=$(grep -m1 -iE 'error|fail' "$log" 2>/dev/null)
    printf '%s' "${line:-The recorder exited without a message. Log: $log}"
}

focused_monitor() {
    hyprctl monitors -j 2>/dev/null | jq -r 'first(.[] | select(.focused) | .name) // empty' 2>/dev/null
}

# window_rects -> one "X,Y WxH" box per window on a visible workspace (a monitor's
# shown special workspace included), for slurp -r.
window_rects() {
    local visible
    visible=$(hyprctl monitors -j 2>/dev/null \
        | jq -c '[.[] | .activeWorkspace.id, (.specialWorkspace.id // 0)] | map(select(. != 0))' 2>/dev/null) || return 1
    hyprctl clients -j 2>/dev/null | jq -r --argjson ws "$visible" '
        .[] | select(.mapped and (.hidden | not) and (.workspace.id as $w | any($ws[]; . == $w)))
        | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
}

# shellcheck disable=SC1091 # Checked separately; relative to this script.
# shellcheck source=scripts/capture/toast.sh
. "${BASH_SOURCE[0]%/*}/toast.sh"

# saved <file> -- the toast, detached; fds 7 and 8 (our locks) stay behind.
saved() {
    saved_toast video-x-generic 'Recording saved' "${1##*/}" "$1" 7>&- 8>&-
}

# ticker <recorder-pid> <since> -- one Waybar refresh a second while the recorder
# runs. When it ends: a stop leaves stopped.<pid>.<since> and the ticker stays silent;
# otherwise the recorder died by itself, so say so (whoever cleaned the state).
ticker() {
    local line="" out=""
    while alive "$1" "$2"; do
        sleep "$ticker_wait"
        signal_bar
    done
    if [ -e "$state_dir/stopped.$1.$2" ]; then
        rm -f "$state_dir/stopped.$1.$2"
    else
        { read -r line < "$state"; } 2>/dev/null
        [[ $line == *"\"pid\":$1,"* ]] && rm -f "$state"
        out=${line#*\"output\":\"}; out=${out%%\"*}
        notify dialog-error 'Recording stopped' "$(first_error)${out:+ Partial file kept: ${out##*/}.}"
    fi
    signal_bar
}

status() {
    local json=0 seconds t
    [ "${1-}" = --json ] && json=1
    if ! read_state; then
        if (( json )); then
            echo '{"text":"","tooltip":"","class":"idle","phase":"idle","seconds":0}'
            return 0
        fi
        echo idle
        return 1
    fi
    t=$(now)
    if [ "$phase" = countdown ]; then
        seconds=$(( started > t ? started - t : 0 ))
    else
        seconds=$(( t - started ))
    fi
    if (( ! json )); then
        echo "$phase $seconds $output"
        return 0
    fi
    case $phase in
        countdown)
            printf '{"text":"<span size=\\\"large\\\" letter_spacing=\\\"4096\\\">%s</span> %d","tooltip":"Recording starts in %d s. Click to cancel.","class":"countdown","phase":"countdown","seconds":%d}\n' \
                "$glyph_timer" "$seconds" "$seconds" "$seconds" ;;
        stopping)
            printf '{"text":"<span size=\\\"large\\\" letter_spacing=\\\"4096\\\">%s</span> saving","tooltip":"Saving the recording","class":"stopping","phase":"stopping","seconds":%d}\n' \
                "$glyph_rec" "$seconds" ;;
        *)
            printf '{"text":"<span size=\\\"large\\\" letter_spacing=\\\"4096\\\">%s</span> %s","tooltip":"Recording. Click to stop and save.","class":"recording","phase":"recording","seconds":%d}\n' \
                "$glyph_rec" "$(fmt "$seconds")" "$seconds" ;;
    esac
}

# countdown <seconds> -- the amber Waybar countdown. record.sh cancel or stop
# (a click on it) sends TERM, which ends this script with nothing recorded.
# At the end the trap changes to "remember it" and stays until start has written
# the recorder's state, so a TERM on the boundary is never lost.
countdown() {
    local t
    t=$(now)
    proc_stat $$
    write_state $$ countdown "" $(( t + $1 )) "$proc_since"
    trap 'rm -f "$state"; signal_bar; exit 0' TERM
    signal_bar
    while (( $(now) < t + $1 )); do
        # A waited-on background sleep, unlike a foreground one, lets the TERM trap run at once.
        sleep "$countdown_wait" 7>&- &
        wait $!
        signal_bar
    done
    trap 'cancelled=1' TERM
}

stop() {
    local rc=0
    [ -d "$state_dir" ] || return 0
    exec 8>"$state_dir/stop.lock" || return 1
    if flock -w $((stop_wait + 2)) 8; then
        stop_locked || rc=$?
    else
        rc=1
    fi
    exec 8>&-
    return "$rc"
}

# stop_locked -- the body of stop, under stop.lock, on a freshly read state.
stop_locked() {
    local i
    read_state || return 0
    if [ "$phase" = countdown ]; then
        kill -TERM "$pid" 2>/dev/null
        return 0
    fi
    # The marker comes first: the ticker must never see the recorder go before it.
    : > "$state_dir/stopped.$pid.$since"
    write_state "$pid" stopping "$output" "$started" "$since"
    signal_bar
    kill -INT "$pid" 2>/dev/null
    for ((i = 0; i < stop_wait * 10; i++)); do
        alive "$pid" "$since" || break
        sleep "$stop_poll_wait"
    done
    if alive "$pid" "$since"; then
        kill -KILL "$pid" 2>/dev/null
        rm -f "$state"
        signal_bar
        notify dialog-error 'Recording not saved' "The recorder did not finish within ${stop_wait} s. Partial file kept: ${output##*/}. Log: $log"
        return 1
    fi
    rm -f "$state"
    signal_bar
    if [ -s "$output" ]; then
        saved "$output"
    else
        notify dialog-error 'Recording not saved' "$(first_error)"
        return 1
    fi
}

# discard_recording -- a cancel that arrived after the recorder was forked.
# Not a stop: the recorder ignores SIGINT until it has installed its handler, so
# a stop this early would wait out stop_wait and leave a broken file. Kill it,
# wait until it is gone, and leave nothing behind.
discard_recording() {
    local i line=""
    kill -KILL "$rec_pid" 2>/dev/null
    { wait "$rec_pid"; } 2>/dev/null
    for ((i = 0; i < 20; i++)); do
        alive "$rec_pid" "$rec_since" || break
        sleep "$discard_poll_wait"
    done
    rm -f "$file" "$state_dir/stopped.$rec_pid.$rec_since"
    { read -r line < "$state"; } 2>/dev/null
    [[ $line == *"\"pid\":$rec_pid,"* ]] && rm -f "$state"
    signal_bar
}

cancel() {
    read_state && [ "$phase" = countdown ] && kill -TERM "$pid" 2>/dev/null
    return 0
}

start() {
    local target=${1-} region=${2-} monitor delay file base n audio="" rec_pid rec_since
    local -a args
    if [ -z "$target" ]; then
        target=$(option capture-rec-target screen)
        case $target in screen|window|region) ;; *) target=screen ;; esac
    fi
    case $target in screen|window|region) ;; *) usage ;; esac
    if [ -n "$region" ]; then
        [ "$target" = region ] || usage
        [[ $region =~ ^[0-9]+x[0-9]+\+-?[0-9]+\+-?[0-9]+$ ]] || usage
    fi

    # A second start while one runs is the toggle: stop it.
    if read_state; then
        stop
        return
    fi
    if ! command -v "$recorder" >/dev/null 2>&1; then
        notify dialog-error 'Recording unavailable' 'Install the gpu-screen-recorder package to record the screen.'
        return 1
    fi
    mkdir -p "$state_dir" || return 1
    # One start at a time: a second press while selecting is dropped.
    exec 7>"$state_dir/start.lock"
    flock -n 7 || return 0
    # Another start may have finished between the first check and the lock.
    if read_state; then
        return 0
    fi

    case $target in
        screen)
            monitor=$(focused_monitor)
            if [ -z "$monitor" ]; then
                notify dialog-error 'Recording failed' 'Hyprland reported no focused monitor.'
                return 1
            fi
            args=(-w "$monitor") ;;
        region)
            # Esc in slurp cancels silently: no toast, nothing written. A region is
            # `-w WxH+X+Y`: gpu-screen-recorder 6.1.3 deprecates `-w region -region`.
            [ -n "$region" ] || region=$(slurp -f '%wx%h+%x+%y') || return 0
            [ -n "$region" ] || return 0
            args=(-w "$region") ;;
        window)
            # The rectangle is fixed now: moving the window later is not followed.
            region=$(window_rects | slurp -r -f '%wx%h+%x+%y') || return 0
            [ -n "$region" ] || return 0
            args=(-w "$region") ;;
    esac

    delay=$(option capture-delay 0)
    [[ $delay =~ ^[0-9]+$ ]] && delay=$((10#$delay)) || delay=0
    cancelled=0
    (( delay > 0 )) && countdown "$delay"

    args+=(-c mp4 -k h264 -ac aac -f 60 -q very_high -cursor yes)
    [ "$(option capture-audio false)" = true ] && audio=default_output
    [ "$(option capture-mic false)" = true ] && audio+="${audio:+|}default_input"
    [ -n "$audio" ] && args+=(-a "$audio")
    if ! mkdir -p "$videos" 2>/dev/null; then
        # After a countdown the state still says so; clear it, or the bar freezes.
        if (( delay > 0 )); then
            rm -f "$state"
            signal_bar
        fi
        notify dialog-error 'Recording failed' "Cannot create $videos."
        return 1
    fi
    printf -v base '%s/Recording_%(%Y-%m-%d_%H-%M-%S)T' "$videos" -1
    file=$base.mp4 n=2
    while [ -e "$file" ]; do
        file=${base}_$n.mp4
        n=$((n + 1))
    done
    args+=(-v no -o "$file")

    # Cancelled on the boundary of the countdown, before anything started.
    if (( cancelled )); then
        rm -f "$state"
        signal_bar
        trap - TERM
        return 0
    fi
    # setsid in a background job execs the recorder in place (the job is not a
    # process-group leader), so $! is the recorder's own pid, and its start time
    # is already final: the state can be written before the exec happens.
    setsid "$recorder" "${args[@]}" </dev/null >"$log" 2>&1 7>&- 8>&- &
    rec_pid=$!
    rec_since=""
    proc_stat "$rec_pid" && rec_since=$proc_since
    rec_since=${rec_since:-0}
    write_state "$rec_pid" recording "$file" "$(now)" "$rec_since"
    signal_bar
    # Test seam: widens the window between the state write and the first check.
    [ -n "${CAPTURE_TEST_HOLD-}" ] && sleep "$CAPTURE_TEST_HOLD"
    # The countdown's TERM trap stays until the ticker runs: a click on the
    # boundary discards the recording (see discard_recording), never half-saves it.
    if (( cancelled )); then
        discard_recording
        trap - TERM
        return 0
    fi
    sleep "$start_wait"
    [ -n "${CAPTURE_TEST_HOLD_LATE-}" ] && sleep "$CAPTURE_TEST_HOLD_LATE"
    if ! alive "$rec_pid" "$rec_since"; then
        if [ -e "$state_dir/stopped.$rec_pid.$rec_since" ]; then
            # A second press stopped it inside this window: that stop owns the cleanup.
            rm -f "$state_dir/stopped.$rec_pid.$rec_since"
            trap - TERM
            return 0
        fi
        rm -f "$state"
        signal_bar
        notify dialog-error 'Recording failed' "$(first_error)"
        trap - TERM
        return 1
    fi
    if (( cancelled )); then
        discard_recording
        trap - TERM
        return 0
    fi
    trap - TERM
    ticker "$rec_pid" "$rec_since" </dev/null >/dev/null 2>&1 7>&- 8>&- &
    return 0
}

case "${1-}" in
    start) shift; start "$@" ;;
    stop) stop ;;
    cancel) cancel ;;
    toggle) shift; if read_state; then stop; else start "$@"; fi ;;
    status) status "${2-}" ;;
    *) usage ;;
esac
