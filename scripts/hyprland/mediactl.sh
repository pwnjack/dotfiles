#!/bin/bash
#
# Transport control for the waybar media module: play-pause, next, previous.
#
# Bare `playerctl play-pause` acts on whichever player registered on the bus
# first, which is not necessarily the one whose title the bar is showing --
# so the module could display Firefox and pause Spotify. Going through
# medialib.sh means the click always lands on the player you can see.
#

# shellcheck source=./medialib.sh
. "$HOME/.config/scripts/hyprland/medialib.sh"

[ $# -gt 0 ] || { echo "usage: ${0##*/} play-pause|next|previous|..." >&2; exit 2; }

player=$(media_player)

# No player on the bus at all: the module is hidden anyway, so do nothing
# rather than let playerctl print to waybar's log once a click.
[ -z "$player" ] && exit 0

if playerctl -p "$player" "$@" 2>/dev/null; then
    # The bar's five-second poll is only a fallback for changes made inside a
    # player. Controls routed through this script refresh the module at once.
    pkill -x -RTMIN+10 waybar 2>/dev/null || true
fi
