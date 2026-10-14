#!/bin/bash
#
# Wrapper for waybar-weather: waits for the network, then streams the
# service's output to waybar line by line, and always emits valid JSON so
# waybar never renders a broken module.
#
# waybar-weather is a long-running service, not a one-shot command: it
# prints a line as soon as it has data (well under a second) and another on
# every update, and never exits on its own. Running it per interval under
# `timeout` meant waybar only saw the first line when the timeout killed it,
# ten seconds after every start. The module is therefore continuous (no
# "interval" in config.jsonc); "restart-interval" brings it back if the
# service dies.
#
# It also swaps waybar-weather's colour emoji for monochrome Nerd Font
# glyphs. The emoji were the only colour glyphs on an otherwise monochrome
# bar, and being bitmap emoji they ignore the wallpaper palette entirely.
# Mapped bar glyphs are wrapped in <span size="large"> (see `large` below)
# to match the bar scale (13px base, glyph promoted by a fifth) -- see waybar/style.css.
#
# An unmapped condition keeps its emoji rather than being replaced by a
# generic glyph: showing the wrong weather is worse than showing a
# mismatched one, and a stray emoji makes the gap visible so it can be
# added here.
#

TEXT_MAP='{"☀":"󰖙","☁":"󰖐","⛅":"󰖕","🌤":"󰖕","⛈":"󰙾","🌩":"󰖓","🌫":"󰖑","🌦":"󰖗","🌧":"󰖖","🌨":"󰖘","🌑":"󰖔","🌒":"󰖔","🌓":"󰖔","🌔":"󰖔","🌕":"󰖔","🌖":"󰖔","🌗":"󰖔","🌘":"󰖔","🌙":"󰖔"}'
TIP_MAP='{"🌅":"󰖜","🌇":"󰖛"}'

# The last rendered reading, shown the moment the module starts: Open-Meteo
# takes anywhere from 0.3 to 4.5 s to answer the service's first request, and
# the bar restarts the module on every reload. A reading older than an hour
# is not shown; the module stays empty until a fresh one arrives. Each bar
# (one per monitor) runs its own wrapper, so every write goes through a
# private temporary file, and the replay passes on only one JSON object.
cache=${XDG_CACHE_HOME:-$HOME/.cache}/waybar-weather.json
if [ -n "$(find "$cache" -mmin -60 2>/dev/null)" ]; then
    jq -cs 'if length == 1 and (.[0] | type) == "object" then .[0] else empty end' "$cache" 2>/dev/null
fi

# The network is up once there is a default route. No ping: ICMP is rate
# limited upstream (a third of the probes to 1.1.1.1 drop), and each failed
# probe cost seconds before the service even started. waybar-weather makes
# its own HTTPS requests and needs nothing more than a route.
check_network() {
    [ -n "$(ip route show default 2>/dev/null)" ]
}

# Wait up to 30 seconds for network to be available
max_wait=30
waited=0
while ! check_network && [ $waited -lt $max_wait ]; do
    sleep 1
    waited=$((waited + 1))
done

# U+FE0F is the emoji variation selector; it trails most of these glyphs and
# would survive the swap as an invisible stray character. If the swap fails
# the untouched original is emitted, but only when it is itself a JSON object:
# anything else prints nothing, and the line is skipped.
render() {
    printf '%s' "$1" | jq -c \
        --argjson text_map "$TEXT_MAP" \
        --argjson tip_map "$TIP_MAP" '
        def strip_vs: gsub("️"; "");
        def swap($m; wrap): reduce ($m | to_entries[]) as $e (.; gsub($e.key; $e.value | wrap));
        def large: "<span size=\"large\" letter_spacing=\"4096\">" + . + "</span>";
        .text = (.text | strip_vs | swap($text_map; large))
        | if .tooltip then .tooltip = (.tooltip | strip_vs | swap($tip_map; .)) else . end
    ' 2>/dev/null || jq -ce 'select(type == "object")' <<< "$1" 2>/dev/null
}

# The service is the wrapper's child, and goes with it: waybar stops the
# module on every reload, and an orphaned service would keep polling.
exec {weather}< <(exec waybar-weather 2>/dev/null)
service=$!
tmp=''
trap 'kill "$service" 2>/dev/null; rm -f "$tmp"' EXIT
trap 'exit 0' TERM INT HUP

# Its log lines go to stderr; only JSON objects are passed on. The service
# re-emits its output every 30 s, so five silent minutes mean it has hung:
# the reading is cleared rather than left on the bar as though current, and
# the next line restores it.
shown=0
while :; do
    IFS= read -r -t 300 line <&"$weather"; status=$?
    if [ "$status" -gt 128 ]; then
        echo '{"text":"","tooltip":"Weather service not responding"}'
        continue
    fi
    [ "$status" -eq 0 ] || break
    [[ $line == \{* ]] || continue
    rendered=$(render "$line")
    [ -n "$rendered" ] || continue
    printf '%s\n' "$rendered"
    if tmp=$(mktemp "$cache.XXXXXX" 2>/dev/null); then
        printf '%s\n' "$rendered" > "$tmp" && mv -f "$tmp" "$cache"
        rm -f "$tmp"; tmp=''
    fi
    shown=1
done

# The service exited. Clear any reading it left behind rather than show it
# as current; waybar restarts the module after its restart-interval.
if [ "$shown" -eq 0 ]; then
    echo '{"text":"","tooltip":"Weather data unavailable"}'
else
    echo '{"text":"","tooltip":"Weather service stopped"}'
fi
