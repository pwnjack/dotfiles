#!/bin/bash
#
# Night Light Control
# Single entry point for hyprsunset -- the keybind, the waybar module and the
# settings panel all call this, and none of them talks to hyprctl directly.
#
# The daemon owns the schedule (hypr/hyprsunset.conf) and switches profiles on
# its own timer, so a manual override set here expires by itself at the next
# scheduled boundary. There is deliberately no state file: the daemon is the
# state, which keeps every surface in agreement.
#
# Usage: nightlight.sh [toggle|on|off|auto|status|waybar]
#

# NIGHTLIGHT_CONFIG is the test seam (test-nightlight-config.sh).
CONFIG="${NIGHTLIGHT_CONFIG:-$HOME/.config/hypr/hyprsunset.conf}"

# Waybar glyphs (CaskaydiaCove Nerd Font).
ICON_WARM="󰖔"
ICON_NEUTRAL="󰖙"

# Notification icons, deliberately NOT the -symbolic names: swaync 0.12.6
# renders nothing at all for Papirus-Dark's symbolic set -- it reserves the
# icon slot and leaves it blank. The non-symbolic variants render fine, and
# these two mirror the bar glyphs above (moon = warm, sun = neutral).
ICON_ON="weather-clear-night"
ICON_OFF="weather-clear"

# Fallbacks for a fresh checkout with no config file yet.
DEFAULT_WARM=4000
DEFAULT_NEUTRAL=6000

action="${1:-toggle}"

# hyprsunset is optional -- stay silent and successful when it is not installed.
if ! command -v hyprsunset >/dev/null 2>&1; then
    [ "$action" = "waybar" ] && echo '{"text": "", "tooltip": ""}'
    exit 0
fi

# Ask the daemon. A crashed daemon leaves a stale socket behind, so probing
# with pgrep would lie -- only a real request tells us if anyone is listening.
hs() { hyprctl hyprsunset "$@" 2>/dev/null; }

# Temperature currently applied, empty when the daemon is not answering.
live_temp() {
    local t
    t=$(hs temperature)
    [[ "$t" =~ ^[0-9]+$ ]] && echo "$t"
}

# Temperature the active profile calls for, i.e. what the schedule wants now.
scheduled_temp() {
    hs profile | sed -n 's/^Temperature:[[:space:]]*\([0-9]\+\)$/\1/p'
}

# Every temperature named by a profile, ascending. A profile line is a literal
# or a hyprlang variable ("temperature = $night_temp"), resolved from its own
# "$name = N" line; a value ends at whitespace or a hyprlang "#" comment.
config_temps() {
    [ -r "$CONFIG" ] || return 0
    awk '
        function value(line,   v) {
            sub(/^[^=]*=[ \t]*/, "", line)
            sub(/[ \t].*$/, "", line)
            v = line
            sub(/#.*$/, "", v)
            return v
        }
        /^[ \t]*\$[A-Za-z_][A-Za-z0-9_]*[ \t]*=/ {
            name = $0; sub(/^[ \t]*\$/, "", name); sub(/[ \t]*=.*$/, "", name)
            vars[name] = value($0)
        }
        /^[ \t]*temperature[ \t]*=/ { temps[++n] = value($0) }
        END {
            for (i = 1; i <= n; i++) {
                t = temps[i]
                if (t ~ /^\$/) t = vars[substr(t, 2)]
                if (t ~ /^[0-9]+$/) print t
            }
        }' "$CONFIG" | sort -n
}

warm_temp() {
    local t
    t=$(config_temps | head -n1)
    echo "${t:-$DEFAULT_WARM}"
}

neutral_temp() {
    local t
    t=$(config_temps | tail -n1)
    echo "${t:-$DEFAULT_NEUTRAL}"
}

# Nudge the waybar module so the icon updates now instead of on the next poll.
refresh_waybar() { pkill -RTMIN+8 waybar 2>/dev/null; }

notify() { notify-send -i "$1" -e "$2" "$3"; }

case "$action" in
    on)
        hs temperature "$(warm_temp)" >/dev/null
        notify "$ICON_ON" "Night Light" "Warm ($(warm_temp)K) until the next schedule change"
        refresh_waybar
        ;;
    off)
        hs temperature "$(neutral_temp)" >/dev/null
        notify "$ICON_OFF" "Night Light" "Neutral ($(neutral_temp)K) until the next schedule change"
        refresh_waybar
        ;;
    toggle)
        current=$(live_temp)
        [ -z "$current" ] && exit 0
        if [ "$current" -le "$(warm_temp)" ]; then
            "$0" off
        else
            "$0" on
        fi
        ;;
    auto)
        # Re-apply whichever profile matches the clock right now.
        hs reset temperature >/dev/null
        scheduled=$(scheduled_temp)
        # The icon follows where the schedule actually landed, since "auto" can
        # resolve to either state depending on the time of day.
        if [ -n "$scheduled" ] && [ "$scheduled" -lt "$(neutral_temp)" ]; then
            notify "$ICON_ON" "Night Light" "Following the schedule (${scheduled}K)"
        else
            notify "$ICON_OFF" "Night Light" "Following the schedule (${scheduled:-?}K)"
        fi
        refresh_waybar
        ;;
    status)
        current=$(live_temp)
        if [ -z "$current" ]; then
            echo "unavailable"
            exit 0
        fi
        scheduled=$(scheduled_temp)
        if [ -n "$scheduled" ] && [ "$current" = "$scheduled" ]; then
            echo "auto ${current}K"
        else
            echo "manual ${current}K (schedule wants ${scheduled:-?}K)"
        fi
        ;;
    waybar)
        current=$(live_temp)
        if [ -z "$current" ]; then
            echo '{"text": "", "tooltip": ""}'
            exit 0
        fi
        scheduled=$(scheduled_temp)
        neutral=$(neutral_temp)

        if [ "$current" -lt "$neutral" ]; then
            icon="$ICON_WARM"
            state="warm"
        else
            icon="$ICON_NEUTRAL"
            state="neutral"
        fi

        # One precise class name, never a space-separated pair: waybar treats
        # the whole string as a single CSS class.
        if [ -n "$scheduled" ] && [ "$current" = "$scheduled" ]; then
            mode="following schedule"
            class="$state"
        else
            mode="manual override until the next schedule change"
            class="${state}-override"
        fi

        printf '{"text": "%s", "alt": "%s", "class": "%s", "tooltip": "Night Light: %sK\\n%s\\n\\nLeft-click: toggle\\nRight-click: follow schedule"}\n' \
            "$icon" "$state" "$class" "$current" "$mode"
        ;;
    *)
        echo "usage: $(basename "$0") [toggle|on|off|auto|status|waybar]" >&2
        exit 1
        ;;
esac
