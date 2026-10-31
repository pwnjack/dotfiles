#!/bin/bash
#
# respawn.sh <command> [args...] -- keep a session daemon alive.
#
# Runs the command and starts it again whenever it dies uncleanly, the way
# systemd's Restart=on-failure would. autostart.lua starts Waybar, SwayNC,
# hypridle and hyprsunset through it, and so do the paths that restart them
# later (scripts/waybar/waybar.sh, the settings panel).
#
# The packaged user units are not used on purpose: when a unit's main process
# crashes, systemd kills everything left in its cgroup, so a Waybar crash
# would close every window opened from the bar and a hypridle crash would
# take a running hyprlock with it. This wrapper keeps the process tree and the
# environment a plain start has, in the plain and the uwsm session alike.
#
# A clean end is final: status 0, or death by SIGHUP, SIGINT, SIGPIPE or
# SIGTERM, so `pkill -x <name>` still stops a daemon for good. bash reports a
# signal death as 128+N, so a daemon that exits 129, 130, 141 or 143 by itself
# reads the same; none of the wrapped daemons uses those codes. The compositor
# going away is final too, checked after the daemon dies and again after the
# delay. A daemon that dies RESPAWN_BURST times within RESPAWN_WINDOW seconds
# is left down, with a notification, instead of spinning.
#
# Before each start the wrapper looks for the daemon by name (`pgrep -x`, so
# the name must fit the kernel's 15 characters): when the settings panel or
# waybar.sh started one while this wrapper waited out its delay, that start
# owns it and this wrapper bows out instead of starting a second copy.

set -u

if [ $# -eq 0 ]; then
    echo "usage: $(basename "$0") <command> [args...]" >&2
    exit 2
fi
if ! command -v "$1" >/dev/null 2>&1; then
    echo "respawn: $1 is not installed" >&2
    exit 127
fi

# compositor_alive -> 0 while the session's Wayland socket exists.
compositor_alive() {
    local socket=${WAYLAND_DISPLAY:-}
    [[ -z $socket || $socket == /* ]] || socket="${XDG_RUNTIME_DIR:-/run/user/$UID}/$socket"
    [ -n "$socket" ] && [ -S "$socket" ]
}

name=${1##*/}
burst=${RESPAWN_BURST:-5}
window=${RESPAWN_WINDOW:-30}
delay=${RESPAWN_DELAY:-1}
starts=()

while :; do
    pgrep -x "$name" >/dev/null 2>&1 && exit 0
    recent=()
    for start in "${starts[@]}"; do
        (( EPOCHSECONDS - start < window )) && recent+=("$start")
    done
    starts=("${recent[@]}")
    if (( ${#starts[@]} >= burst )); then
        logger -t respawn "$1 died $burst times in ${window}s; not restarting it" 2>/dev/null || true
        command -v notify-send >/dev/null 2>&1 &&
            notify-send -u critical "$1 keeps crashing" "It died $burst times in ${window}s and was not restarted." 2>/dev/null
        exit 1
    fi
    starts+=("$EPOCHSECONDS")

    "$@"
    status=$?
    case $status in
        0|129|130|141|143) exit "$status" ;;
    esac
    # A daemon that lost its compositor is not crashing; there is nothing to
    # restart it into, and the session may also end during the delay.
    compositor_alive || exit "$status"
    logger -t respawn "$1 exited with status $status; restarting it" 2>/dev/null || true
    sleep "$delay"
    compositor_alive || exit "$status"
done
