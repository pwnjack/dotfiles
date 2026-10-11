#!/bin/bash
# The one reader and writer of the local calendar copy, through khal. Used by
# sync.sh (agenda.json), the calendar card and the settings panel.
#   cal.sh range <YYYY-MM-DD> <days>   visible events, normalized, with epochs
#   cal.sh day <YYYY-MM-DD>            one day's visible events
#   cal.sh month <YYYY-MM>             {"busy":[day numbers]}
#   cal.sh year <YYYY>                 {"counts":[12 numbers]}
#   cal.sh calendars                   [{"name","color","writable"}]
#   cal.sh add                         one stdin line {"calendar","ics"} -> {"ok":true}
#   cal.sh inspect CALENDAR UID EPOCH  {"alert","recurring","invitation","allDay","hash"}
#   cal.sh update                      one stdin line {"calendar","uid","occurrence","scope","hash","changes","moveTo"?}
#   cal.sh delete                      one stdin line {"calendar","uid","occurrence","scope","hash"}
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
    # The stamps come from a file, not --argjson: a year of events exceeds the argument size limit.
    jq -c --rawfile st <(printf '%s\n' "$stamps") \
        '($st | split("\n") | map(select(length > 0) | tonumber)) as $s
        | [to_entries[] | .value + {startEpoch: $s[2 * .key], endEpoch: $s[2 * .key + 1]}]' <<<"$events"
}

# known_calendars — display names of every collection in the local copy.
known_calendars() {
    local dir
    for dir in "$cal_data"/*/; do
        [[ -d $dir ]] || continue
        cat "$dir/displayname" 2>/dev/null || basename "$dir"
    done
}

# hide_declined — reads khal's events on stdin and drops the instances the account
# declined. $cal_state/declined holds "calendar<TAB>uid<TAB>key" rules, written by
# sync.sh: "*" hides every instance, "<start>" hides the one starting then, and
# "!<start>" shows one again under a declined series. A missing file hides nothing.
hide_declined() {
    local declined=$cal_state/declined
    [[ -r $declined ]] || declined=/dev/null
    # The rules are indexed once, by "calendar<TAB>uid": {all, hide, show}, so each
    # event is a constant-time lookup, not a scan of every rule.
    jq -c --rawfile declined "$declined" '
        ($declined | split("\n") | map(select(length > 0) | split("\t")) | map(select(length == 3))
            | reduce .[] as $r ({};
                ($r[0] + "\t" + $r[1]) as $k
                | (.[$k] // {all: false, hide: {}, show: {}}) as $v
                | .[$k] = (if $r[2] == "*" then $v | .all = true
                           elif $r[2][0:1] == "!" then $v | .show[$r[2][1:]] = true
                           else $v | .hide[$r[2]] = true end))) as $index
        | map(. as $e
            | ($index[$e.calendar + "\t" + $e.uid] // {all: false, hide: {}, show: {}}) as $r
            | ($e.start // "") as $s
            | select((($r.hide[$s] // false) or ($r.all and (($r.show[$s] // false) | not))) | not))'
}

# list <from> <days> — visible events from khal, normalized. Hidden and
# skipped calendars are left out by khal itself. khal exits 2 on a -d name it
# does not know or is given twice, and lists everything when -d covers every
# calendar, so the names are deduplicated, limited to existing calendars, and
# an all-excluded set never reaches khal.
list() {
    local name known remaining=0 raw err
    local -a exclude=() seen=()
    known=$(known_calendars)
    while IFS= read -r name; do
        [[ -n $name ]] || continue
        grep -qxF -- "$name" <<<"$known" || continue
        if ((${#seen[@]})) && printf '%s\n' "${seen[@]}" | grep -qxF -- "$name"; then continue; fi
        seen+=("$name"); exclude+=(-d "$name")
    done < <(cal_excluded)
    while IFS= read -r name; do
        [[ -n $name ]] || continue
        if ! ((${#seen[@]})) || ! printf '%s\n' "${seen[@]}" | grep -qxF -- "$name"; then remaining=1; fi
    done <<<"$known"
    if [[ -n $known ]] && ((!remaining)); then echo '[]'; return; fi
    err=$(mktemp "${TMPDIR:-/tmp}/cal-khal.XXXXXX")
    if ! raw=$("$khal" list --day-format '' --json uid --json title --json location --json calendar --json calendar-color \
        --json start --json end --json repeat-pattern "${exclude[@]}" "$1" "${2}d" 2>"$err"); then
        name=$(grep -v '^[[:space:]]*$' "$err" | tail -n1 || true)
        rm -f "$err"
        die "${name:-khal could not list events}"
    fi
    rm -f "$err"
    jq -s -f "$cal_dir/khal-events.jq" <<<"$raw" | hide_declined | with_epochs
}

# need_list <from> <days> — list into $events; on failure print its error
# JSON and exit, which a pipeline into jq would swallow.
need_list() { events=$(list "$@") || { printf '%s\n' "$events"; exit 1; }; }

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
    after_write
}

# calendar_dir <name> — the folder holding that calendar (vdirsyncer's displayname).
calendar_dir() {
    local dir
    for dir in "$cal_data"/*/; do
        [[ $(cat "$dir/displayname" 2>/dev/null || basename "$dir") == "$1" ]] && { printf '%s' "${dir%/}"; return 0; }
    done
    return 1
}
# find_event <calendar> <uid> — the file in that calendar whose UID line matches exactly.
find_event() {
    local dir file
    dir=$(calendar_dir "$1") || return 1
    while IFS= read -r -d '' file; do
        if grep -qxF -e "UID:$2" -e "UID:$2"$'\r' "$file"; then printf '%s' "$file"; return 0; fi
    done < <(find "$dir" -maxdepth 1 -name '*.ics' -print0)
    return 1
}
# account_addresses — the account's own identities as a JSON array: writable.sh's
# file, or the Apple ID as mailto: until that file exists.
account_addresses() {
    local list acct
    list=$(grep -v '^[[:space:]]*$' "$cal_state/addresses" 2>/dev/null || true)
    if [[ -z $list ]]; then
        acct=$(cal_account)
        [[ -z $acct ]] || list="mailto:${acct,,}"
    fi
    jq -Rc -s 'split("\n") | map(select(length > 0))' <<<"$list"
}
# after_write — the same local-first finish as an add.
after_write() {
    bash "$cal_dir/sync.sh" --render >/dev/null 2>&1 || true
    [[ ${CALENDAR_NO_SYNC:-} ]] || setsid -f bash "$cal_dir/sync.sh" </dev/null >/dev/null 2>&1
    echo '{"ok":true}'
}
# helper <op> <file> [jq args...] — ics-edit.py with the file's text and the request
# fields. Prints its answer when it is {"ok":true,...}; otherwise prints an
# {"ok":false} carrying its error, or a fixed one when it printed none (a crash
# leaves only a traceback on stderr), and returns 1.
helper() {
    local op=$1 file=$2 out msg; shift 2
    if out=$(jq -cn --rawfile raw "$file" --argjson addresses "$(account_addresses)" "$@" \
        '{raw: $raw, addresses: $addresses} + ($req // {})' | python3 -I "$cal_dir/ics-edit.py" "$op") \
        && jq -e '.ok == true' <<<"$out" >/dev/null 2>&1; then
        printf '%s\n' "$out"
        return 0
    fi
    msg=$(jq -r '.error // empty' <<<"$out" 2>/dev/null || true)
    jq -cn --arg m "${msg:-The event could not be changed}" '{ok:false, error:$m}'
    return 1
}

inspect() {
    local file
    file=$(find_event "$1" "$2") || die "That event is no longer in $1"
    helper inspect "$file" --argjson req "$(jq -cn --argjson o "${3:-0}" '{occurrence: $o}')"
}

edit() {   # edit update|delete — one JSON request line on stdin
    local op=$1 line calendar uid file out new target dir tmp
    IFS= read -r line || true
    calendar=$(jq -r '.calendar // ""' <<<"$line" 2>/dev/null) || die 'Expected one JSON request'
    uid=$(jq -r '.uid // ""' <<<"$line")
    [[ $(calendars | jq -r --arg n "$calendar" '.[] | select(.name == $n) | .writable') == true ]] || die "$calendar is read-only"
    file=$(find_event "$calendar" "$uid") || die "That event is no longer in $calendar"
    [[ $(sha256sum < "$file" | cut -d' ' -f1) == "$(jq -r '.hash // ""' <<<"$line")" ]] \
        || die 'This event changed on your iPhone; open it again'
    out=$(helper "$op" "$file" --argjson req "$(jq -c '{occurrence, scope, changes}' <<<"$line")") || { printf '%s\n' "$out"; exit 1; }
    new=$(jq -r '.raw' <<<"$out")
    if [[ -z $new ]]; then rm -f -- "$file"; after_write; return; fi
    target=$(jq -r '.moveTo // ""' <<<"$line")
    dir=$(dirname "$file")
    if [[ -n $target && $target != "$calendar" ]]; then
        [[ $(calendars | jq -r --arg n "$target" '.[] | select(.name == $n) | .writable') == true ]] || die "$target is read-only"
        dir=$(calendar_dir "$target") || die "Unknown calendar: $target"
        [[ ! -e $dir/$(basename "$file") ]] || die "$target already has this event"
    fi
    tmp=$(mktemp "$dir/.edit.XXXXXX")
    printf '%s' "$new" > "$tmp"
    # A rename gives the file a new inode, which is how vdirsyncer sees the change.
    mv -f -- "$tmp" "$dir/$(basename "$file")"
    [[ $dir == "$(dirname "$file")" ]] || rm -f -- "$file"
    after_write
}

case ${1:-} in
    range) [[ $# == 3 ]] || die 'Usage: cal.sh range DATE DAYS'; need_list "$2" "$3"; printf '%s\n' "$events" ;;
    day) [[ $# == 2 ]] || die 'Usage: cal.sh day DATE'; need_list "$2" 1; printf '%s\n' "$events" ;;
    month)
        [[ $# == 2 && $2 =~ ^[0-9]{4}-[0-9]{2}$ ]] || die 'Usage: cal.sh month YYYY-MM'
        days=$(date -d "$2-01 +1 month -1 day" +%d)
        need_list "$2-01" "$((10#$days))"
        jq -c --arg month "$2" -f "$cal_dir/busy.jq" <<<"$events" ;;
    year)
        [[ $# == 2 && $2 =~ ^[0-9]{4}$ ]] || die 'Usage: cal.sh year YYYY'
        days=$(( ($(date -d "$(( $2 + 1 ))-01-01" +%s) - $(date -d "$2-01-01" +%s) + 43200) / 86400 ))
        need_list "$2-01-01" "$days"
        jq -c --arg year "$2" '[.[] | select(.start[0:4] == $year)] as $e
            | [range(1; 13) as $m | [$e[] | select((.start[5:7] | tonumber) == $m)] | length] | {counts: .}' <<<"$events" ;;
    calendars) calendars ;;
    add) add ;;
    inspect) [[ $# == 4 ]] || die 'Usage: cal.sh inspect CALENDAR UID OCCURRENCE'; inspect "$2" "$3" "$4" ;;
    update) edit update ;;
    delete) edit delete ;;
    *) die 'Usage: cal.sh range|day|month|year|calendars|add|inspect|update|delete' ;;
esac
