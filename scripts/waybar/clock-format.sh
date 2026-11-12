#!/bin/bash
# Render Waybar's clock format from options/clock into the include that
# waybar/config.jsonc names. Always leaves the include in place (24 h unless the
# option says 12h), so a fresh checkout or a garbled option still shows a clock.
# The include path is fixed to match config.jsonc, which cannot expand variables.
set -euo pipefail
clock=${CLOCK_OPTION:-$HOME/.config/options/clock}
include=${CLOCK_INCLUDE:-$HOME/.local/state/waybar/clock.jsonc}
# shellcheck source=scripts/lib/options.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/options.sh"
# Weekday and day of month lead, two spaces before the time: the same gap
# the bar uses inside a module, so date and time read as one readout. The L
# flag is what makes Waybar name the day in the session's LC_TIME (the
# settings panel's Formats row) rather than always in English; its "locale"
# option alone does not. Only the time is bold, as Pango markup inside the
# one placeholder: the date is the quieter half of the readout.
time='%H:%M' suffix=''
if [[ $(option "$clock") == 12h ]]; then time='%I:%M' suffix=' %p'; fi
# Seconds (options/clock-seconds, the Bar page) are the bar's alone: the lock
# screen keeps its hour/minute layout. They need a one-second interval, which
# is why the main config must not set clock.interval either.
seconds=${clock%/*}/clock-seconds interval=''
if [[ $(option "$seconds") == enabled ]]; then time+=':%S' interval=', "interval": 1'; fi
format="{:L%a %d  <b>$time$suffix</b>}"
mkdir -p "${include%/*}"
tmp=$(mktemp "$include.XXXXXX")
trap 'rm -f "$tmp"' EXIT
printf '{ "clock": { "format": "%s"%s } }\n' "$format" "$interval" > "$tmp"
mv -f "$tmp" "$include"
# Reload through waybar.sh, never a bare USR2: Proton VPN's tray icon does not
# re-register after one, and waybar.sh restores it. Only a running bar is
# reloaded -- waybar.sh would start one, and a settings change must not bring
# back a bar the user toggled off.
if [[ ${1:-} != --no-reload ]] && pgrep -x waybar >/dev/null 2>&1; then
    bash "$(dirname -- "${BASH_SOURCE[0]}")/waybar.sh" || true
fi
