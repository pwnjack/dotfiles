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
# "location", "place" (the first line of the bar's tooltip, its name for the
# location) and "fetchedAt" (epoch seconds), saved as
# $XDG_CACHE_HOME/weather-popover/forecast.json. Otherwise one reason line on
# stderr, no JSON, exit 1, and the saved copy stays as it was. An answer
# without every series the card reads is such a failure.
#
# `forecast.sh --cached` prints the saved copy and exits 0 when it is for the
# bar's current location and in the bar's unit, and exits 1 with no output
# otherwise. It never uses the network; how old a copy may be is the caller's
# decision.
#
set -uo pipefail

cache="${XDG_CACHE_HOME:-$HOME/.cache}"
bar="$cache/waybar-weather.json"
saved="$cache/weather-popover/forecast.json"

fail() { echo "$1" >&2; exit 1; }

# One reading of the bar's cache, taken once, so the coordinates, the place's
# name and the unit belong together even if the bar replaces the file during
# the request. Exactly one object: anything else is not the wrapper's file.
reading=$(jq -cs 'if length == 1 and (.[0] | type) == "object" then .[0] else empty end' "$bar" 2>/dev/null) || reading=''
# The shape is checked because the value goes into a URL, and the cache is a
# file any of the user's processes can write.
location=$(jq -er '.location | strings
    | select(test("^-?[0-9]{1,3}\\.[0-9]{1,6},-?[0-9]{1,3}\\.[0-9]{1,6}$"))' <<< "$reading" 2>/dev/null) || location=''
place=$(jq -r '.tooltip | strings | split("\n")[0]' <<< "$reading" 2>/dev/null) || place=''
# The card speaks the bar's unit, which is set in the service's own config.
unit='°C'
if jq -e '.text | strings | contains("°F")' <<< "$reading" >/dev/null 2>&1; then unit='°F'; fi

# What the card's model indexes. A forecast without all of it is refused both
# when it arrives and when it is read back, so it can neither replace a good
# copy nor be drawn.
# shellcheck disable=SC2016  # jq's variables, not the shell's
usable='
    def full($group; $keys): ($group.time | type) == "array" and ($group.time | length) > 0
        and all($keys[]; ($group[.] | type) == "array" and ($group[.] | length) == ($group.time | length));
    def usable: (.current | type) == "object"
        and full(.hourly; ["temperature_2m", "weather_code", "is_day"])
        and full(.daily; ["weather_code", "temperature_2m_max", "temperature_2m_min"]);'

if [ "${1-}" = --cached ]; then
    [ -n "$location" ] || exit 1
    jq -e --arg location "$location" --arg unit "$unit" "$usable"'
        usable and .location == $location and (.fetchedAt | type) == "number"
        and .current_units.temperature_2m == $unit' "$saved" >/dev/null 2>&1 || exit 1
    cat -- "$saved"
    exit 0
fi
[ $# -eq 0 ] || fail 'Usage: forecast.sh [--cached]'

for binary in curl jq; do
    command -v "$binary" >/dev/null 2>&1 || fail "$binary is required for the forecast."
done
[ -n "$location" ] || fail 'The bar has no location yet.'

url="https://api.open-meteo.com/v1/forecast?latitude=${location%,*}&longitude=${location#*,}"
url+='&timezone=auto&timeformat=unixtime&forecast_days=7&forecast_hours=48'
url+='&current=temperature_2m,apparent_temperature,weather_code,is_day'
url+='&hourly=temperature_2m,weather_code,is_day'
url+='&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset'
if [ "$unit" = '°F' ]; then url+='&temperature_unit=fahrenheit'; fi

answer=$(curl -fsS --max-time 10 "$url" 2>/dev/null) || fail 'No connection to Open-Meteo.'
forecast=$(jq -ce --arg location "$location" --arg place "$place" --argjson now "$(date +%s)" "$usable"'
    select(usable) | .location = $location | .place = $place | .fetchedAt = $now' <<< "$answer" 2>/dev/null) \
    || fail 'Open-Meteo sent no forecast.'

# Replaced by rename, so the card never reads half a file. Saving is best
# effort on purpose: a cache that cannot be written costs the next opening its
# head start, and that is no reason to withhold a forecast already in hand.
if mkdir -p "${saved%/*}" 2>/dev/null && tmp=$(mktemp "$saved.XXXXXX" 2>/dev/null); then
    if printf '%s\n' "$forecast" > "$tmp"; then mv -f "$tmp" "$saved" 2>/dev/null; fi
    rm -f "$tmp"
fi
printf '%s\n' "$forecast"
