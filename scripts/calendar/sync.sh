#!/bin/bash
# The only path that talks to iCloud. The timer, the card (on open and after an
# add), the bar's right-click and the settings panel all run this.
#   sync.sh            discover (daily), metasync + sync, then render and signal
#   sync.sh --render   render agenda.json and signal only: no network
# Locks: a second sync waits for the first (sync.lock), and so do cal.sh's writes;
# rendering has its own lock, so an add renders at once even while a slow sync runs.
# A sync whose account is removed while it runs (a sign-out) writes nothing.
# shellcheck disable=SC2154  # cal_* paths come from lib.sh
set -euo pipefail
# shellcheck source=scripts/calendar/lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
mkdir -p "$cal_runtime" "$cal_state"
status_file=$cal_runtime/status.json
khal=${CAL_KHAL:-khal}
now=$(date +%s)

signal() { pkill -RTMIN+12 waybar 2>/dev/null || true; }

# render — writes agenda.json from cal.sh. Returns 1 with render_error set when the
# render lock stays busy, cal.sh fails or its output is not an array; the last agenda
# then stays in place, so the bar keeps what it showed.
render() {
    local tmp out
    render_error=''
    exec 7>"$cal_runtime/render.lock"
    flock -w "${CALENDAR_LOCK_WAIT:-30}" 7 || { render_error='Calendar is busy; try again in a moment'; return 1; }
    if [[ -z $(cal_account) ]]; then rm -f "$cal_runtime/agenda.json"; return 0; fi
    tmp=$(mktemp "$cal_runtime/agenda.XXXXXX")
    if out=$(bash "$cal_dir/cal.sh" range "$(date +%F)" 8); then
        if jq -e 'type == "array"' <<<"$out" >/dev/null && printf '%s\n' "$out" > "$tmp" \
            && mv -f "$tmp" "$cal_runtime/agenda.json"; then
            return 0
        fi
        render_error='Calendar output was not understood'
    else
        render_error=$(jq -r '.error // empty' <<<"$out" 2>/dev/null || true)
        render_error=${render_error:-Calendar could not be read}
    fi
    rm -f "$tmp"
    return 1
}

# write_status <state> <kind> <message> <lastSuccess|null>
write_status() {
    local tmp
    tmp=$(mktemp "$status_file.XXXXXX")
    jq -n --arg state "$1" --arg kind "$2" --arg message "$3" --argjson last "$4" --argjson at "$now" \
        '{state: $state, kind: $kind, message: $message, lastSuccess: $last, lastAttempt: $at}' > "$tmp"
    mv -f "$tmp" "$status_file"
}

# scan_declined — rebuilds $cal_state/declined (the instances the account declined,
# which cal.sh hides). Written through a temp file, so a failed scan or publish
# keeps the last list and logs one line; never fatal, so the sync stays ok.
scan_declined() {
    local tmp
    tmp=$(mktemp "$cal_state/declined.XXXXXX") || return 0
    if python3 -I "$cal_dir/declined.py" "$cal_data" "$cal_state/addresses" "$(cal_account)" > "$tmp" 2>/dev/null \
        && mv -f "$tmp" "$cal_state/declined"; then
        return 0
    fi
    rm -f -- "$tmp" 2>/dev/null || true
    echo 'calendar: could not scan declined invitations; keeping the previous list' >&2
    return 0
}

if [[ ${1:-} == --render ]]; then
    [[ -e $cal_state/declined ]] || scan_declined
    rc=0
    render || rc=1
    signal
    exit "$rc"
fi

# Read before the lock: an account removed while this sync waited for it is the
# sign-out's doing, and the sync writes nothing.
had_account=$(cal_account)
exec 8>"$cal_runtime/sync.lock"
# Another sync holding the lock for two minutes is stuck or slow; the timer
# catches up next time.
flock -w "${CALENDAR_LOCK_WAIT:-120}" 8 || exit 0
prev_state=$(jq -r '.state // ""' "$status_file" 2>/dev/null || true)
last_success=$(jq -c '.lastSuccess // null' "$status_file" 2>/dev/null || echo null)

if [[ -z $(cal_account) ]]; then
    [[ -z $had_account ]] || exit 0
    write_status none "" "" null
    render || true
    signal
    exit 0
fi

state=ok kind='' message=''
if ! command -v vdirsyncer >/dev/null 2>&1; then
    state=failed kind=tool message='vdirsyncer is not installed'
elif ! command -v "$khal" >/dev/null 2>&1; then
    state=failed kind=tool message='Calendar tools not installed'
    rm -f "$cal_runtime/agenda.json"
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

# Signed out while the sync ran: the copy is being removed, so nothing is published.
[[ -n $(cal_account) ]] || exit 0
if [[ $state == ok ]]; then
    scan_declined
    # A render that fails is a failed sync, not a quiet stale agenda.
    render || { state=failed kind=other message=$render_error; }
else
    render || true
fi
if [[ $state == ok ]]; then
    write_status ok "" "" "$now"
else
    write_status failed "$kind" "$message" "$last_success"
    if [[ $prev_state != failed ]]; then
        notify-send -a Calendar -i x-office-calendar 'Calendar' "Sync with iCloud failed: $message" 2>/dev/null || true
    fi
fi
signal
