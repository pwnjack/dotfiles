#!/bin/bash
# Click on Waybar's volume icon: toggle the sound popover. Requests are
# serialized, and the Quickshell process exits when the popover closes, so
# nothing of it runs while it is closed.
set -euo pipefail
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/sound-popover"
[[ $# -eq 0 ]] || { echo 'Usage: sound-popover.sh' >&2; exit 2; }
# Run from a Waybar click, stderr goes nowhere: every failure is also a notification.
fail() {
    notify-send -a Sound 'Sound' "$1" 2>/dev/null || true
    echo "$1" >&2
    exit 1
}
command -v qs >/dev/null 2>&1 || fail 'Install quickshell to show the sound popover.'
for binary in flock hyprctl jq; do
    command -v "$binary" >/dev/null 2>&1 || fail "$binary is required for the sound popover."
done
mkdir -p "$cache_dir" || fail "Cannot create $cache_dir for the sound popover."
exec 9>"$cache_dir/launch.lock" || fail "Cannot open the sound popover lock in $cache_dir."
flock -w 10 9 || fail 'The sound popover is still starting; try again.'
entry="$config_dir/quickshell/sound/shell.qml"
ipc() { qs -p "$entry" ipc call sound "$1" 9>&-; }
if ipc toggle >/dev/null 2>&1; then exit 0; fi
# shellcheck source=scripts/theming/palette.sh
source "$config_dir/scripts/theming/palette.sh" || fail 'Cannot load the theme palette for the sound popover.'
declare -a wal
# shellcheck disable=SC2034  # read by role_load, wal_role and wal_render
declare -A role=()
# Tested as a condition: under set -e a failure inside $(...) would end this
# script silently. A palette that was never generated reads as palette.sh's
# fallback; only a failing helper leaves nothing exported, and then the
# popover uses its built-in colours.
if wal_load && role_load && foreground=$(wal_readable_on "${wal[0]}") \
    && accent=$(wal_role primary) && on_accent=$(wal_role on_primary); then
    export SOUND_BACKGROUND="${wal[0]}" SOUND_ACCENT="$accent"
    export SOUND_FOREGROUND="$foreground" SOUND_ON_ACCENT="$on_accent"
fi
export SOUND_FONT SOUND_CURSOR_X SOUND_BAR_POSITION
SOUND_FONT=$(head -n1 "$config_dir/options/font" 2>/dev/null || true)
# Waybar does not say where on the module the click landed; the cursor does.
SOUND_CURSOR_X=$(hyprctl cursorpos -j 2>/dev/null | jq -r '.x // -1' 2>/dev/null || echo -1)
SOUND_BAR_POSITION=$(head -n1 "$config_dir/options/bar-position" 2>/dev/null || echo top)
qs -p "$entry" --no-duplicate --daemonize >"$cache_dir/session.log" 2>&1 9>&- \
    || fail "The sound popover failed to start; see $cache_dir/session.log"
# Hold the lock until IPC answers, so a quick second click closes this
# instance instead of racing a second start.
for ((attempt = 0; attempt < 60; attempt++)); do
    if ipc ping >/dev/null 2>&1; then exit 0; fi
    sleep 0.05
done
fail "The sound popover did not answer; see $cache_dir/session.log"
