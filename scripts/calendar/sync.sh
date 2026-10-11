#!/bin/bash
# The only path that talks to iCloud. The timer, the card (on open and after an
# add), the bar's right-click and the settings panel all run this.
#   sync.sh            discover (daily), metasync + sync, then render and signal
#   sync.sh --render   render agenda.json and signal only: no network
# Locks: a second sync waits for the first (sync.lock); rendering has its own
# lock, so an add renders at once even while a slow sync runs.
# shellcheck disable=SC2154  # cal_* paths come from lib.sh
set -euo pipefail
# shellcheck source=scripts/calendar/lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
mkdir -p "$cal_runtime" "$cal_state"
status_file=$cal_runtime/status.json
now=$(date +%s)

signal() { pkill -RTMIN+12 waybar 2>/dev/null || true; }

render() {
    exec 7>"$cal_runtime/render.lock"
    flock -w 30 7 || return 0
    if [[ -z $(cal_account) ]]; then rm -f "$cal_runtime/agenda.json"; return 0; fi
    local tmp
    tmp=$(mktemp "$cal_runtime/agenda.XXXXXX")
    if bash "$cal_dir/cal.sh" range "$(date +%F)" 8 > "$tmp" && jq -e 'type == "array"' "$tmp" >/dev/null; then
        mv -f "$tmp" "$cal_runtime/agenda.json"
    else
        rm -f "$tmp"
    fi
}

# write_status <state> <kind> <message> <lastSuccess|null>
write_status() {
    local tmp
    tmp=$(mktemp "$status_file.XXXXXX")
    jq -n --arg state "$1" --arg kind "$2" --arg message "$3" --argjson last "$4" --argjson at "$now" \
        '{state: $state, kind: $kind, message: $message, lastSuccess: $last, lastAttempt: $at}' > "$tmp"
    mv -f "$tmp" "$status_file"
}

if [[ ${1:-} == --render ]]; then
    render
    signal
    exit 0
fi

exec 8>"$cal_runtime/sync.lock"
# Another sync holding the lock for two minutes is stuck or slow; the timer
# catches up next time.
flock -w 120 8 || exit 0
prev_state=$(jq -r '.state // ""' "$status_file" 2>/dev/null || true)
last_success=$(jq -c '.lastSuccess // null' "$status_file" 2>/dev/null || echo null)

if [[ -z $(cal_account) ]]; then
    write_status none "" "" null
    render
    signal
    exit 0
fi

state=ok kind='' message=''
if ! command -v vdirsyncer >/dev/null 2>&1; then
    state=failed kind=tool message='vdirsyncer is not installed'
else
    out=''
    stamp=$cal_state/discovered
    if [[ ! -e $stamp || -n $(find "$stamp" -mmin +1440 2>/dev/null) ]]; then
        # discover asks before creating each local folder; the answer is always yes.
        # Not `yes |`: under pipefail, yes's SIGPIPE would fail the pipeline.
        if out=$(vdirsyncer discover icloud < <(yes 2>/dev/null) 2>&1); then
            touch "$stamp"
            # Re-classify the calendars while the collection list is fresh.
            # Best effort: a missing or failing script keeps the previous files.
            bash "${CALENDAR_WRITABLE:-$cal_dir/writable.sh}" >/dev/null 2>&1 || true
        else
            state=failed
        fi
    fi
    if [[ $state == ok ]] && ! out=$( { vdirsyncer metasync && vdirsyncer sync; } 2>&1 ); then state=failed; fi
    if [[ $state == failed ]]; then
        # Classify on error lines only: progress lines name collections by UUID.
        errs=$({ grep -iE '^[[:space:]]*(error|critical)' <<<"$out" || true; })
        [[ -n $errs ]] || errs=$out
        if grep -qiE '(^|[^0-9a-z])401([^0-9a-z]|$)|unauthori[sz]ed' <<<"$errs"; then
            kind=auth message='Sign-in rejected'
        elif grep -qiE 'name resolution|could not resolve|connection (refused|reset)|timed out|network is unreachable|cannot connect' <<<"$errs"; then
            kind=network message='iCloud is unreachable'
        else
            kind=other message=$({ grep -v '^[[:space:]]*$' <<<"$errs" || true; } | tail -n1 | cut -c1-160)
            message=${message:-Sync failed}
        fi
    fi
fi

if [[ $state == ok ]]; then
    write_status ok "" "" "$now"
else
    write_status failed "$kind" "$message" "$last_success"
    if [[ $prev_state != failed ]]; then
        notify-send -a Calendar -i x-office-calendar 'Calendar' "Sync with iCloud failed: $message" 2>/dev/null || true
    fi
fi
render
signal
