#!/bin/bash
# The calendar card (quickshell/calendar). Entry points:
#   month     the clock's click: the month, upcoming folded
#   upcoming  the next-event pill's click: upcoming unfolded
#   new       Super+Shift+E: the new-event sheet
# A running card is toggled over IPC (the card applies the transition table);
# otherwise one is started. Requests are serialised; the process exits on close.
set -euo pipefail
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/calendar-card"
entry=${1:-}
[[ $# -eq 1 && $entry =~ ^(month|upcoming|new)$ ]] || { echo 'Usage: calendar-card.sh month|upcoming|new' >&2; exit 2; }
fail() {
    notify-send -a Calendar 'Calendar' "$1" 2>/dev/null || true
    echo "$1" >&2
    exit 1
}
command -v qs >/dev/null 2>&1 || fail 'Install quickshell to show the calendar.'
mkdir -p "$cache_dir" || fail "Cannot create $cache_dir for the calendar."
exec 9>"$cache_dir/launch.lock" || fail "Cannot open the calendar lock in $cache_dir."
flock -w 10 9 || fail 'The calendar is still starting; try again.'
shell="$config_dir/quickshell/calendar/shell.qml"
ipc() { qs -p "$shell" ipc call calendar "$@" 9>&-; }
if ipc toggle "$entry" >/dev/null 2>&1; then exit 0; fi
# shellcheck source=scripts/theming/palette.sh
source "$config_dir/scripts/theming/palette.sh" || fail 'Cannot load the theme palette for the calendar.'
declare -a wal
if wal_load && foreground=$(wal_readable_on "${wal[0]}") && on_accent=$(wal_readable_on "${wal[4]}"); then
    export CALENDAR_BACKGROUND="${wal[0]}" CALENDAR_ACCENT="${wal[4]}"
    export CALENDAR_FOREGROUND="$foreground" CALENDAR_ON_ACCENT="$on_accent"
fi
locale=${LC_ALL:-${LC_TIME:-${LANG:-en_US.UTF-8}}}
export CALENDAR_ENTRY="$entry" CALENDAR_LOCALE="${locale%%.*}"
export CALENDAR_FONT CALENDAR_BAR_POSITION CALENDAR_CLOCK
CALENDAR_FONT=$(head -n1 "$config_dir/options/font" 2>/dev/null || true)
CALENDAR_BAR_POSITION=$(head -n1 "$config_dir/options/bar-position" 2>/dev/null || echo top)
CALENDAR_CLOCK=$(head -n1 "$config_dir/options/clock" 2>/dev/null || echo 24h)
qs -p "$shell" --no-duplicate --daemonize >"$cache_dir/session.log" 2>&1 9>&- \
    || fail "The calendar failed to start; see $cache_dir/session.log"
for ((attempt = 0; attempt < 60; attempt++)); do
    if ipc ping >/dev/null 2>&1; then exit 0; fi
    sleep 0.05
done
fail "The calendar did not answer; see $cache_dir/session.log"
