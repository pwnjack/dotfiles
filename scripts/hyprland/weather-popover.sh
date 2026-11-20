#!/bin/bash
# Click on Waybar's custom/weather: toggle the weather card. Nothing of it
# runs while it is closed; scripts/weather/forecast.sh fetches for it.
set -euo pipefail
[[ $# -eq 0 ]] || { echo 'Usage: weather-popover.sh' >&2; exit 2; }
# shellcheck source=scripts/lib/qs-launch.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/qs-launch.sh"
qs_launch weather weather Weather 'the weather card'
if qs_ipc toggle >/dev/null 2>&1; then exit 0; fi
qs_theme WEATHER
qs_anchor WEATHER
locale=${LC_ALL:-${LC_TIME:-${LANG:-en_US.UTF-8}}}
export WEATHER_CLOCK WEATHER_LOCALE="${locale%%.*}"
# shellcheck disable=SC2154  # config_dir is set by qs-launch.sh
WEATHER_CLOCK=$(option "$config_dir/options/clock" 24h)
qs_start
