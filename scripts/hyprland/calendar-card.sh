#!/bin/bash
# The calendar card (quickshell/calendar). Entry points:
#   month     the clock's click: the month, upcoming folded
#   upcoming  the next-event pill's click: upcoming unfolded
#   new       Super+Shift+E: the new-event sheet
# A running card is toggled over IPC (the card applies the transition table);
# otherwise one is started.
set -euo pipefail
entry=${1:-}
[[ $# -eq 1 && $entry =~ ^(month|upcoming|new)$ ]] || { echo 'Usage: calendar-card.sh month|upcoming|new' >&2; exit 2; }
# shellcheck source=scripts/lib/qs-launch.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/qs-launch.sh"
qs_launch calendar calendar Calendar 'the calendar'
if qs_ipc toggle "$entry" >/dev/null 2>&1; then exit 0; fi
qs_theme CALENDAR
locale=${LC_ALL:-${LC_TIME:-${LANG:-en_US.UTF-8}}}
export CALENDAR_ENTRY="$entry" CALENDAR_LOCALE="${locale%%.*}"
export CALENDAR_BAR_POSITION CALENDAR_CLOCK
CALENDAR_BAR_POSITION=$(qs_option bar-position top)
CALENDAR_CLOCK=$(qs_option clock 24h)
qs_start
