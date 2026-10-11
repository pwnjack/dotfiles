#!/bin/bash
# The one reader and writer of the local calendar copy, through khal. Used by
# sync.sh (agenda.json), the calendar card and the settings panel.
#   cal.sh range <YYYY-MM-DD> <days>   visible events, normalized, with epochs
#   cal.sh day <YYYY-MM-DD>            one day's visible events
#   cal.sh month <YYYY-MM>             {"busy":[day numbers]}
#   cal.sh year <YYYY>                 {"counts":[12 numbers]}
#   cal.sh calendars                   [{"name","color","writable"}]
#   cal.sh add                         one stdin line {"calendar","ics"} -> {"ok":true}
# Errors print {"ok":false,"error":"..."} and exit 1.
# shellcheck disable=SC2154  # cal_* paths come from lib.sh
set -euo pipefail
# shellcheck source=scripts/calendar/lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
khal=${CAL_KHAL:-khal}

die() { jq -cn --arg m "$1" '{ok:false, error:$m}'; exit 1; }
command -v "$khal" >/dev/null 2>&1 || die 'khal is not installed'

# with_epochs — adds startEpoch/endEpoch to normalized events. One date(1)
# call for all stamps; an all-day end becomes the midnight after its last day
# ("DATE tomorrow"), so a DST day keeps its real length.
with_epochs() {
    local events stamps
    events=$(cat)
    if [[ $(jq 'length' <<<"$events") == 0 ]]; then echo '[]'; return; fi
    stamps=$(jq -r '.[] | .start, (if .allDay then .end + " tomorrow" else .end end)' <<<"$events" | date -f - +%s) \
        || die 'Cannot read event times'
    jq -c --argjson s "$(jq -Rs 'split("\n") | map(select(length > 0) | tonumber)' <<<"$stamps")" \
        '[to_entries[] | .value + {startEpoch: $s[2 * .key], endEpoch: $s[2 * .key + 1]}]' <<<"$events"
}

# list <from> <days> — visible events from khal, normalized. Hidden and
# skipped calendars are left out by khal itself.
list() {
    local name
    local -a exclude=()
    while IFS= read -r name; do exclude+=(-d "$name"); done < <(cal_excluded)
    "$khal" list --day-format '' --json uid --json title --json location --json calendar --json calendar-color \
        --json start --json end --json repeat-pattern "${exclude[@]}" "$1" "${2}d" 2>/dev/null \
        | jq -s -f "$cal_dir/khal-events.jq" | with_epochs
}

# calendars — from vdirsyncer's metadata, so names match khal's. Skipped
# collections are omitted; colours are cut from #RRGGBBAA to #RRGGBB.
calendars() {
    local dir name color writable
    local -a rows=()
    local skipped
    skipped=$(cal_skipped)
    for dir in "$cal_data"/*/; do
        [[ -d $dir ]] || continue
        name=$(cat "$dir/displayname" 2>/dev/null || basename "$dir")
        if [[ -n $skipped ]] && grep -qxF -- "$name" <<<"$skipped"; then continue; fi
        color=$(cat "$dir/color" 2>/dev/null || true)
        [[ $color =~ ^(#[0-9A-Fa-f]{6})([0-9A-Fa-f]{2})?$ ]] && color=${BASH_REMATCH[1]} || color=
        writable=true
        if [[ -r $cal_state/readonly ]] && grep -qxF -- "$name" "$cal_state/readonly"; then writable=false; fi
        rows+=("$(jq -cn --arg n "$name" --arg c "$color" --argjson w "$writable" '{name:$n, color:$c, writable:$w}')")
    done
    if ((${#rows[@]} == 0)); then echo '[]'; return; fi
    printf '%s\n' "${rows[@]}" | jq -cs 'sort_by(.name)'
}

add() {
    local line calendar ics tmp known err
    IFS= read -r line || true
    calendar=$(jq -r '.calendar // ""' <<<"$line" 2>/dev/null) || die 'Expected one JSON request'
    # -j and a sentinel keep the payload's trailing CRLF through $(...).
    ics=$(jq -j '.ics // ""' <<<"$line"; printf x)
    ics=${ics%x}
    [[ $ics == BEGIN:VCALENDAR* ]] || die 'The request is not a calendar event'
    known=$(calendars | jq -r --arg n "$calendar" '.[] | select(.name == $n) | .writable')
    [[ -n $known ]] || die "Unknown calendar: $calendar"
    [[ $known == true ]] || die "$calendar is read-only"
    mkdir -p "$cal_runtime"
    tmp=$(mktemp "$cal_runtime/new.XXXXXX.ics")
    printf '%s' "$ics" > "$tmp"
    if ! err=$("$khal" import --batch -a "$calendar" "$tmp" 2>&1); then
        rm -f "$tmp"
        die "${err:-khal could not save the event}"
    fi
    rm -f "$tmp"
    # Local first: the card and the bar see the event at once; iCloud gets it
    # from a detached sync that outlives the card.
    bash "$cal_dir/sync.sh" --render >/dev/null 2>&1 || true
    [[ ${CALENDAR_NO_SYNC:-} ]] || setsid -f bash "$cal_dir/sync.sh" </dev/null >/dev/null 2>&1
    echo '{"ok":true}'
}

case ${1:-} in
    range) [[ $# == 3 ]] || die 'Usage: cal.sh range DATE DAYS'; list "$2" "$3" ;;
    day) [[ $# == 2 ]] || die 'Usage: cal.sh day DATE'; list "$2" 1 ;;
    month)
        [[ $# == 2 && $2 =~ ^[0-9]{4}-[0-9]{2}$ ]] || die 'Usage: cal.sh month YYYY-MM'
        days=$(date -d "$2-01 +1 month -1 day" +%d)
        list "$2-01" "$((10#$days))" | jq -c --arg month "$2" -f "$cal_dir/busy.jq" ;;
    year)
        [[ $# == 2 && $2 =~ ^[0-9]{4}$ ]] || die 'Usage: cal.sh year YYYY'
        days=$(( ($(date -d "$(( $2 + 1 ))-01-01" +%s) - $(date -d "$2-01-01" +%s) + 43200) / 86400 ))
        list "$2-01-01" "$days" | jq -c '[range(1; 13) as $m | [.[] | select((.start[5:7] | tonumber) == $m)] | length] | {counts: .}' ;;
    calendars) calendars ;;
    add) add ;;
    *) die 'Usage: cal.sh range|day|month|year|calendars|add' ;;
esac
