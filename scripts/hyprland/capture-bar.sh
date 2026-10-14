#!/bin/bash
# Super+Shift+S / Super+Shift+R: open the capture strip on the Screenshot or
# Record tab. A second press of the same key closes it; the other key switches
# tab. Super+Shift+R while a recording runs (or counts down) stops it instead,
# without opening anything. Requests are serialized, and the Quickshell
# process exits when the strip closes. The capturing is
# scripts/hyprland/screenshot.sh and scripts/capture/record.sh.
set -euo pipefail
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/capture-bar"
mode="${1:-screenshot}"
case "$mode" in
    screenshot|record) ;;
    *) echo 'Usage: capture-bar.sh [screenshot|record]' >&2; exit 2 ;;
esac
# Run from a keybind, stderr goes nowhere: every failure is also a notification.
fail() {
    notify-send -a Capture 'Capture' "$1" 2>/dev/null || true
    echo "$1" >&2
    exit 1
}
record="$config_dir/scripts/capture/record.sh"
if [ "$mode" = record ] && "$record" status >/dev/null 2>&1; then
    exec "$record" stop
fi
command -v qs >/dev/null 2>&1 || fail 'Install quickshell to show the capture bar.'
command -v flock >/dev/null || fail 'flock is required for the capture bar.'
mkdir -p "$cache_dir" || fail "Cannot create $cache_dir for the capture bar."
exec 9>"$cache_dir/launch.lock" || fail "Cannot open the capture bar lock in $cache_dir."
flock -w 10 9 || fail 'The capture bar is still starting; try again.'
entry="$config_dir/quickshell/capture/shell.qml"
ipc() { qs -p "$entry" ipc call capture "$@" 9>&-; }
if ipc toggle "$mode" >/dev/null 2>&1; then exit 0; fi
# shellcheck source=scripts/theming/palette.sh
source "$config_dir/scripts/theming/palette.sh" || fail 'Cannot load the theme palette for the capture bar.'
declare -a wal
# shellcheck disable=SC2034  # read by role_load, wal_role and wal_render
declare -A role=()
# Tested as a condition: under set -e a failure inside $(...) would end this
# script silently. If the palette cannot be read, nothing is exported and the
# strip uses its built-in palette.
if wal_load && role_load && foreground=$(wal_readable_on "${wal[0]}") \
    && accent=$(wal_role primary) && on_accent=$(wal_role on_primary); then
    export CAPTURE_BACKGROUND="${wal[0]}" CAPTURE_ACCENT="$accent"
    export CAPTURE_FOREGROUND="$foreground" CAPTURE_ON_ACCENT="$on_accent"
fi
export CAPTURE_FONT CAPTURE_MODE="$mode"
CAPTURE_FONT=$(head -n1 "$config_dir/options/font" 2>/dev/null || true)
qs -p "$entry" --no-duplicate --daemonize >"$cache_dir/session.log" 2>&1 9>&- \
    || fail "The capture bar failed to start; see $cache_dir/session.log"
# Hold the lock until IPC answers, so a quick second press closes this
# instance instead of racing a second start.
for ((attempt = 0; attempt < 60; attempt++)); do
    if ipc ping >/dev/null 2>&1; then exit 0; fi
    sleep 0.05
done
fail "The capture bar did not answer; see $cache_dir/session.log"
