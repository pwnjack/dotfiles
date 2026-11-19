#!/bin/bash
#
# Tests for scripts/weather/forecast.sh. A stub `curl` first on PATH answers
# from the card's fixture (Berlin) and records every call, and the cache is a
# temporary directory, so the suite uses neither the network nor the user's
# location.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORECAST="$TEST_DIR/forecast.sh"
FIXTURE="$TEST_DIR/../../quickshell/weather/test/fixtures/forecast.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

CACHE="$TMP/cache"
SAVED="$CACHE/weather-popover/forecast.json"
mkdir -p "$TMP/bin" "$CACHE"
# What Open-Meteo sends: the fixture without the two keys the script adds.
jq -c 'del(.location, .place, .fetchedAt)' "$FIXTURE" > "$TMP/answer"

# CURL_MODE picks the answer: ok, down (curl's own failure), nodays, partial
# (a series the card reads is missing), short (one is shorter than its times),
# garbage.
cat > "$TMP/bin/curl" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$TMP/calls"
case "\${CURL_MODE:-ok}" in
    ok) cat "$TMP/answer" ;;
    down) exit 6 ;;
    nodays) jq -c '.daily.time = []' "$TMP/answer" ;;
    partial) jq -c 'del(.hourly.is_day)' "$TMP/answer" ;;
    short) jq -c '.daily.temperature_2m_max |= .[1:]' "$TMP/answer" ;;
    garbage) echo '<html>busy</html>' ;;
esac
EOF
chmod +x "$TMP/bin/curl"

# bar <json> -- the bar's cached reading.
bar() { printf '%s\n' "$1" > "$CACHE/waybar-weather.json"; }
calls() { [ -e "$TMP/calls" ] && wc -l < "$TMP/calls" || echo 0; }
# The status goes to a file: callers wrap run in $(...), a subshell.
run_status() { cat "$TMP/status"; }
run() {
    PATH="$TMP/bin:$PATH" XDG_CACHE_HOME="$CACHE" bash "$FORECAST" "$@" 2>"$TMP/stderr"
    echo $? > "$TMP/status"
}

BERLIN='{"text":"8.5°C","tooltip":"Berlin, Germany\nLight rain","location":"52.52,13.41"}'

echo "forecast.sh"

# --- a fetch ------------------------------------------------------------------

bar "$BERLIN"
before=$(date +%s)
out=$(run)
assert_eq "$(run_status)" 0 "a fetch exits 0"
assert_json_field "$out" .location "52.52,13.41" "the forecast names its location"
assert_json_field "$out" ".fetchedAt >= $before" true "and when it was fetched"
assert_json_field "$out" .place "Berlin, Germany" "and the bar's name for the place"
assert_json_field "$out" '.daily.time | length' 7 "with Open-Meteo's seven days"
assert_eq "$(cat "$SAVED")" "$out" "the saved copy is what was printed"
call=$(tail -n 1 "$TMP/calls")
assert_contains "$call" "latitude=52.52&longitude=13.41" "the request is for the bar's location"
assert_contains "$call" "timeformat=unixtime&forecast_days=7&forecast_hours=48" "seven days and 48 hours, in epoch times"
assert_contains "$call" "--max-time 10" "with a time limit"
assert_not_contains "$call" "temperature_unit" "in Celsius while the bar reads Celsius"

bar '{"text":"47.3°F","location":"52.52,13.41"}'
out=$(run)
assert_json_field "$out" .place "" "a reading without a tooltip gives an empty place"
assert_contains "$(tail -n 1 "$TMP/calls")" "&temperature_unit=fahrenheit" "in Fahrenheit when the bar reads Fahrenheit"

# --- the saved copy -----------------------------------------------------------

bar "$BERLIN"
saved=$(cat "$SAVED")
n=$(calls)
out=$(run --cached)
assert_eq "$(run_status)" 0 "--cached exits 0 for the same location"
assert_eq "$out" "$saved" "and prints the saved copy"
assert_eq "$(calls)" "$n" "without a request"

bar '{"text":"8.5°C","location":"48.86,2.35"}'
out=$(run --cached)
assert_eq "$(run_status)" 1 "--cached exits 1 once the bar is somewhere else"
assert_eq "$out" "" "with no output"

bar '{"text":"8.5°C"}'
run --cached >/dev/null
assert_eq "$(run_status)" 1 "--cached exits 1 while the bar has no location"

# The copy is in Celsius; a bar that now reads Fahrenheit must not be shown it.
bar '{"text":"47.3°F","tooltip":"Berlin, Germany","location":"52.52,13.41"}'
run --cached >/dev/null
assert_eq "$(run_status)" 1 "--cached exits 1 once the bar reads another unit"

# A copy the card could not draw is not handed to it.
bar "$BERLIN"
cp "$SAVED" "$TMP/good"
jq -c 'del(.hourly.weather_code)' "$TMP/good" > "$SAVED"
out=$(run --cached)
assert_eq "$(run_status)$out" 1 "--cached refuses a copy with a series missing"
cp "$TMP/good" "$SAVED"
run --cached >/dev/null
assert_eq "$(run_status)" 0 "and accepts the whole one again"

# --- failures leave the saved copy alone --------------------------------------

bar "$BERLIN"
for mode in down nodays partial short garbage; do
    out=$(CURL_MODE=$mode run)
    assert_eq "$(run_status)" 1 "$mode: the fetch fails"
    assert_eq "$out" "" "$mode: with no JSON"
    assert_eq "$(cat "$SAVED")" "$saved" "$mode: and the saved copy is untouched"
done
CURL_MODE=down run >/dev/null
assert_eq "$(cat "$TMP/stderr")" "No connection to Open-Meteo." "a failed request says so"
CURL_MODE=nodays run >/dev/null
assert_eq "$(cat "$TMP/stderr")" "Open-Meteo sent no forecast." "an answer without days says so"
CURL_MODE=partial run >/dev/null
assert_eq "$(cat "$TMP/stderr")" "Open-Meteo sent no forecast." "and so does one with a series missing"

# --- no usable location -------------------------------------------------------

n=$(calls)
for reading in '{"text":"8.5°C"}' \
    '{"text":"8.5°C","location":"52.52,13.41&latitude=0"}' \
    '{"text":"8.5°C","location":"52.52;13.41"}' \
    '{"text":"8.5°C","location":"52.52,13.41 --output /tmp/x"}' \
    '{"text":"8.5°C","location":52.52}' \
    '{"location":"52.52,13.41"}{"location":"48.86,2.35"}' \
    '["52.52,13.41"]'; do
    bar "$reading"
    out=$(run)
    assert_eq "$(run_status)$(cat "$TMP/stderr")" "1The bar has no location yet." "no location in: $reading"
done
rm -f "$CACHE/waybar-weather.json"
run >/dev/null
assert_eq "$(run_status)$(cat "$TMP/stderr")" "1The bar has no location yet." "no bar reading at all"
assert_eq "$(calls)" "$n" "none of them reached curl"

# --- nothing saved yet --------------------------------------------------------

bar "$BERLIN"
rm -rf "$CACHE/weather-popover"
run --cached >/dev/null
assert_eq "$(run_status)" 1 "--cached exits 1 with nothing saved"
out=$(run)
assert_eq "$(cat "$SAVED")" "$out" "a fetch creates the cache directory"

test_summary "forecast.sh"
