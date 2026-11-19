#!/bin/bash
#
# The weather card's forecast: one Open-Meteo request for the place the bar's
# weather is for, and the saved copy of its answer. Nothing else talks to
# Open-Meteo for the card; the bar's own reading is waybar-weather's.
#
# The place is the "location" key ("<latitude>,<longitude>") that
# waybar/waybar-weather-wrapper.sh keeps in $XDG_CACHE_HOME/waybar-weather.json.
# It is read whatever that file's age: the bar hides a reading after an hour,
# but the place it was for is still the best known.
#
# Exit status: 0 with the forecast on stdout, which is Open-Meteo's answer plus
# "location" and "fetchedAt" (epoch seconds), saved as
# $XDG_CACHE_HOME/weather-popover/forecast.json. Otherwise one reason line on
# stderr, no JSON, exit 1, and the saved copy stays as it was.
#
# `forecast.sh --cached` prints the saved copy and exits 0 when it is for the
# bar's current location, and exits 1 with no output otherwise. It never uses
# the network; how old a copy may be is the caller's decision.
#
set -uo pipefail

cache="${XDG_CACHE_HOME:-$HOME/.cache}"
bar="$cache/waybar-weather.json"
saved="$cache/weather-popover/forecast.json"

fail() { echo "$1" >&2; exit 1; }

# The shape is checked here because the value goes into a URL, and the cache
# is a file any of the user's processes can write.
location=$(jq -er '.location | strings
    | select(test("^-?[0-9]{1,3}\\.[0-9]{1,6},-?[0-9]{1,3}\\.[0-9]{1,6}$"))' "$bar" 2>/dev/null) || location=''

if [ "${1-}" = --cached ]; then
    [ -n "$location" ] || exit 1
    jq -e --arg location "$location" '.location == $location and (.fetchedAt | type) == "number"' \
        "$saved" >/dev/null 2>&1 || exit 1
    cat -- "$saved"
    exit 0
fi
[ $# -eq 0 ] || fail 'Usage: forecast.sh [--cached]'

for binary in curl jq; do
    command -v "$binary" >/dev/null 2>&1 || fail "$binary is required for the forecast."
done
[ -n "$location" ] || fail 'The bar has no location yet.'

# The card speaks the bar's unit, which is set in the service's own config.
unit=''
if jq -er '.text | strings | select(contains("°F"))' "$bar" >/dev/null 2>&1; then
    unit='&temperature_unit=fahrenheit'
fi
url="https://api.open-meteo.com/v1/forecast?latitude=${location%,*}&longitude=${location#*,}"
url+='&timezone=auto&timeformat=unixtime&forecast_days=7&forecast_hours=48'
url+='&current=temperature_2m,apparent_temperature,weather_code,is_day'
url+='&hourly=temperature_2m,weather_code,is_day'
url+='&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset'
url+=$unit

answer=$(curl -fsS --max-time 10 "$url" 2>/dev/null) || fail 'No connection to Open-Meteo.'
forecast=$(jq -ce --arg location "$location" --argjson now "$(date +%s)" '
    select((.current | type) == "object"
        and (.hourly.time | arrays | length) > 0
        and (.daily.time | arrays | length) > 0)
    | .location = $location | .fetchedAt = $now' <<< "$answer" 2>/dev/null) \
    || fail 'Open-Meteo sent no forecast.'

# Replaced by rename, so the card never reads half a file. A cache that cannot
# be written costs only the next opening's head start.
if mkdir -p "${saved%/*}" 2>/dev/null && tmp=$(mktemp "$saved.XXXXXX" 2>/dev/null); then
    if printf '%s\n' "$forecast" > "$tmp"; then mv -f "$tmp" "$saved"; fi
    rm -f "$tmp"
fi
printf '%s\n' "$forecast"
