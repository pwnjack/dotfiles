#!/bin/bash
#
# Tests for waybar/waybar-weather-wrapper.sh.
#
# Standalone, exit 1 on any failure. The wrapper runs as a subprocess, as
# Waybar runs it, with a stub `waybar-weather` first on PATH that prints one
# reading and exits; the wrapper then prints its "stopped" line and ends. A
# stub `ip` answers the default-route probe, and the cache and config
# directories are temporary, so neither the network nor the user's reading or
# service configuration is used.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAYBAR_DIR="$TEST_DIR/../../waybar"
WRAPPER="$WAYBAR_DIR/waybar-weather-wrapper.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/ip" <<'EOF'
#!/bin/bash
echo 'default via 192.0.2.1 dev eth0'
EOF
# The stub records its arguments and prints the reading the test chose.
cat > "$TMP/bin/waybar-weather" <<EOF
#!/bin/bash
printf '%s\n' "\$@" > "$TMP/args"
cat "$TMP/reading"
EOF
chmod +x "$TMP/bin/ip" "$TMP/bin/waybar-weather"

# run <tooltip as a JSON string body> -- the wrapper's first output line.
run() {
    printf '{"text":"☀️ 8.5°C","tooltip":"%s","class":["waybar-weather","clear"]}\n' "$1" > "$TMP/reading"
    rm -rf "$TMP/cache" && mkdir -p "$TMP/cache"
    PATH="$TMP/bin:$PATH" XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config" \
        bash "$WRAPPER" 2>/dev/null | head -n 1
}

TIP='Berlin, Germany\nSunny\nWind: 11.3 → 22.3 km/h (W)\n\n🌅 7:34 a.m. • 🌇 4:07 p.m.'

echo "waybar-weather-wrapper.sh"

# --- the coordinate line ------------------------------------------------------

out=$(run "$TIP\\n@52.52,13.41")
assert_json_field "$out" .location "52.52,13.41" "the coordinate line becomes the location"
assert_json_lacks "$out" .tooltip "@" "and leaves the tooltip"
assert_json_field "$out" '.tooltip | split("\n") | length' 5 "which keeps every other line"
assert_json_field "$out" '.tooltip | endswith("p.m.")' true "and ends where the service's own text ends"
assert_json_field "$(cat "$TMP/cache/waybar-weather.json")" .location "52.52,13.41" "the cache carries the location"
assert_json_contains "$out" .text '<span size="large"' "the condition glyph is still swapped in"
assert_json_lacks "$out" .text "☀" "and the emoji is gone"

out=$(run "$TIP\\n@-33.87,-151.21")
assert_json_field "$out" .location "-33.87,-151.21" "negative coordinates are a location too"

# --- no coordinate line -------------------------------------------------------

out=$(run "$TIP")
assert_json_field "$out" 'has("location")' false "a reading without the line has no location"
assert_json_field "$out" '.tooltip | split("\n") | length' 5 "and its tooltip is whole"

out=$(run "$TIP\\n@home")
assert_json_field "$out" 'has("location")' false "a last line that is not coordinates is not a location"
assert_json_contains "$out" .tooltip "@home" "and stays in the tooltip"

out=$(run "Berlin, Germany\\n@52.52,13.41\\nSunny")
assert_json_field "$out" 'has("location")' false "coordinates anywhere but the last line are left alone"

# --- the service's configuration ----------------------------------------------

assert_eq "$(sed -n 1p "$TMP/args")" "-config" "the service is started with -config"
config=$(sed -n 2p "$TMP/args")
assert_eq "$(basename "$config")" "weather.toml" "naming weather.toml"
if [ -f "$config" ]; then pass "which exists"; else fail "which exists" "missing: $config"; fi
assert_eq "$(tail -n 1 "$WAYBAR_DIR/weather.toml")" \
    '@{{floatFormat .Latitude 2}},{{floatFormat .Longitude 2}}"""' \
    "its tooltip ends with the coordinate line"

# A user's own service configuration is not overridden.
mkdir -p "$TMP/config/waybar-weather"
echo 'units = "imperial"' > "$TMP/config/waybar-weather/config.toml"
run "$TIP" >/dev/null
assert_eq "$(cat "$TMP/args")" "" "a user's own config leaves the service without -config"

test_summary "waybar-weather-wrapper.sh"
