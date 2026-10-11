#!/bin/bash
# Waybar custom/agenda: the next event beside the clock. Reads only
# agenda.json (rendered by scripts/calendar/sync.sh, which also sends signal
# 12), options/bar-agenda and options/clock, so its once-a-minute run starts
# no Python and touches no network. Empty text hides the module.
#   soon   in progress, or starting within 12 h (default)
#   today  in progress, or starting before midnight
#   next   in progress, or the next one however far (a later day shows its date)
#   hidden nothing (the module does no work)
# An all-day event today shows when no timed one does.
set -euo pipefail
runtime=${CALENDAR_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/tmp}/calendar}
options=${CALENDAR_OPTIONS:-$HOME/.config/options}
icon=$'\U000F00ED'
empty() { echo '{"text":"","class":"empty"}'; exit 0; }

mode=soon
read -r mode 2>/dev/null < "$options/bar-agenda" || true
case $mode in soon|today|next) ;; hidden) empty ;; *) mode=soon ;; esac
[[ -r $runtime/agenda.json ]] || empty

now=${AGENDA_NOW:-$(date +%s)}
midnight=$(date -d "$(date -d "@$now" +%F) tomorrow" +%s)
case $mode in
    soon) until=$((now + 43200)) ;;
    today) until=$((midnight - 1)) ;;
    next) until=9999999999 ;;
esac
pick=$(jq -c --argjson now "$now" --argjson until "$until" '
    ([.[] | select(.allDay | not)] | sort_by(.startEpoch)) as $timed
    | [ ($timed | map(select(.startEpoch <= $now and $now < .endEpoch)) | first | select(.) | . + {kind: "now"}),
        ($timed | map(select(.startEpoch > $now and .startEpoch <= $until)) | first | select(.) | . + {kind: "soon"}),
        ([.[] | select(.allDay and .startEpoch <= $now and $now < .endEpoch)] | first | select(.) | . + {kind: "allday"}) ]
    | first // empty' "$runtime/agenda.json" 2>/dev/null) || empty
[[ -n $pick ]] || empty

kind=$(jq -r .kind <<<"$pick")
title=$(jq -r .title <<<"$pick")
start=$(jq -r .startEpoch <<<"$pick")
(( ${#title} > 24 )) && title="${title:0:23}…"
title=${title//&/"&amp;"}; title=${title//</"&lt;"}; title=${title//>/"&gt;"}

case $kind in
    now) text="now · $title" ;;
    allday) text=$title ;;
    soon)
        # In "next" mode an event on a later day shows its date; every other
        # soon event shows its time, in the clock's 12/24 h.
        if [[ $mode == next ]] && (( start >= midnight )); then
            text="$(date -d "@$start" '+%a %d') · $title"
        else
            fmt='%H:%M'
            [[ $(cat "$options/clock" 2>/dev/null) == 12h ]] && fmt='%I:%M %p'
            text="$(date -d "@$start" "+$fmt") $title"
        fi ;;
esac
jq -cn --arg text "$icon $text" --arg class "$kind" '{text: $text, class: $class}'
