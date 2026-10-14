#!/bin/bash
# Click on Waybar's custom/updates: toggle the update card. Requests are
# serialized, and the Quickshell process exits when the card closes. The
# update itself is scripts/updates/updates-run.sh and outlives the card.
set -euo pipefail
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/updates-popover"
[[ $# -eq 0 ]] || { echo 'Usage: updates-popover.sh' >&2; exit 2; }
# Run from a Waybar click, stderr goes nowhere: every failure is also a notification.
fail() {
    notify-send -a Updates 'Updates' "$1" 2>/dev/null || true
    echo "$1" >&2
    exit 1
}
command -v qs >/dev/null 2>&1 || fail 'Install quickshell to show the update card.'
command -v flock >/dev/null || fail 'flock is required for the update card.'
mkdir -p "$cache_dir" || fail "Cannot create $cache_dir for the update card."
exec 9>"$cache_dir/launch.lock" || fail "Cannot open the update card lock in $cache_dir."
flock -w 10 9 || fail 'The update card is still starting; try again.'
entry="$config_dir/quickshell/updates/shell.qml"
ipc() { qs -p "$entry" ipc call updates "$1" 9>&-; }
if ipc toggle >/dev/null 2>&1; then exit 0; fi
# shellcheck source=scripts/theming/palette.sh
source "$config_dir/scripts/theming/palette.sh" || fail 'Cannot load the theme palette for the update card.'
declare -a wal
# shellcheck disable=SC2034  # read by role_load, wal_role and wal_render
declare -A role=()
# Tested as a condition: under set -e a failure inside $(...) would end this
# script silently. If the palette cannot be read, nothing is exported and the
# card uses its built-in palette.
if wal_load && role_load && foreground=$(wal_readable_on "${wal[0]}") \
    && accent=$(wal_role primary) && on_accent=$(wal_role on_primary); then
    export UPDATES_BACKGROUND="${wal[0]}" UPDATES_ACCENT="$accent"
    export UPDATES_FOREGROUND="$foreground" UPDATES_ON_ACCENT="$on_accent"
fi
export UPDATES_FONT UPDATES_CURSOR_X UPDATES_BAR_POSITION
UPDATES_FONT=$(head -n1 "$config_dir/options/font" 2>/dev/null || true)
# Waybar does not say where on the module the click landed; the cursor does.
UPDATES_CURSOR_X=$(hyprctl cursorpos -j 2>/dev/null | jq -r '.x // -1' 2>/dev/null || echo -1)
UPDATES_BAR_POSITION=$(head -n1 "$config_dir/options/bar-position" 2>/dev/null || echo top)
qs -p "$entry" --no-duplicate --daemonize >"$cache_dir/session.log" 2>&1 9>&- \
    || fail "The update card failed to start; see $cache_dir/session.log"
# Hold the lock until IPC answers, so a quick second click closes this
# instance instead of racing a second start.
for ((attempt = 0; attempt < 60; attempt++)); do
    if ipc ping >/dev/null 2>&1; then exit 0; fi
    sleep 0.05
done
fail "The update card did not answer; see $cache_dir/session.log"
