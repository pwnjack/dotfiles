#!/bin/bash
# Waybar custom/agenda: the next event beside the clock. Reads only
# agenda.json (rendered by scripts/calendar/sync.sh, which also sends signal
# 12), options/bar-agenda and options/clock, so its once-a-minute run starts
# no Python and touches no network. Empty text hides the module; the tooltip
# is the shown event in full (title, time, calendar, location).
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

# Unit separators, not tabs: read collapses runs of a whitespace IFS, so an
# empty calendar would shift the location into its place.
IFS=$'\x1f' read -r kind start end all_day title calendar location < <(jq -r \
    '[.kind, .startEpoch, .endEpoch, .allDay, .title, (.calendar // ""), (.location // "")]
     | map(tostring | gsub("[\u001f\n]"; " ")) | join("\u001f")' <<<"$pick")
# Pango markup: the bar text and the tooltip are both parsed as markup.
esc() { local t=${1//&/"&amp;"}; t=${t//</"&lt;"}; printf '%s' "${t//>/"&gt;"}"; }
fmt='%H:%M'
[[ $(cat "$options/clock" 2>/dev/null) == 12h ]] && fmt='%I:%M %p'
short=$title
(( ${#short} > 24 )) && short="${short:0:23}…"
short=$(esc "$short")

case $kind in
    now) text="now · $short" ;;
    allday) text=$short ;;
    soon)
        # In "next" mode an event on a later day shows its date; every other
        # soon event shows its time, in the clock's 12/24 h.
        if [[ $mode == next ]] && (( start >= midnight )); then
            text="$(date -d "@$start" '+%a %d') · $short"
        else
            text="$(date -d "@$start" "+$fmt") $short"
        fi ;;
esac
# The tooltip is the event in full: the whole title, when, and where. Days
# are named whenever the event is not within today, since the bar text may show
# only a time: a later day, or an event running past midnight either way.
today=$(date -d "$(date -d "@$now" +%F)" +%s)
day() { date -d "@$1" '+%a %d'; }
last=$((end - 1))     # the end is exclusive: an event ending at midnight ends the day before
if [[ $all_day == true ]]; then
    when='all day'
    [[ $(date -d "@$start" +%F) != "$(date -d "@$last" +%F)" ]] && when="$(day "$start") – $(day "$last") · all day"
elif [[ $(date -d "@$start" +%F) != "$(date -d "@$last" +%F)" ]]; then
    when="$(day "$start") $(date -d "@$start" "+$fmt") – $(day "$end") $(date -d "@$end" "+$fmt")"
else
    when="$(date -d "@$start" "+$fmt")–$(date -d "@$end" "+$fmt")"
    (( start < today || start >= midnight )) && when="$(day "$start") · $when"
fi
tooltip="<b>$(esc "$title")</b>"$'\n'"$when"
[[ -n $calendar ]] && tooltip+=" · $(esc "$calendar")"
[[ -n $location ]] && tooltip+=$'\n'"$(esc "$location")"
jq -cn --arg text "$icon $text" --arg class "$kind" --arg tooltip "$tooltip" '{text: $text, class: $class, tooltip: $tooltip}'
