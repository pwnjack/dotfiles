#!/bin/bash
# Super+H: toggle the keybindings overlay. Requests are serialized, and the
# Quickshell process exits when the overlay closes.
set -euo pipefail
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/keybinds-overlay"
[[ $# -eq 0 ]] || { echo 'Usage: keybinds-overlay.sh' >&2; exit 2; }
# Run from a keybind, stderr goes nowhere: every failure is also a notification,
# or a broken Super+H would look like a dead key.
fail() {
    notify-send -a Keybindings 'Keybindings' "$1" 2>/dev/null || true
    echo "$1" >&2
    exit 1
}
command -v qs >/dev/null 2>&1 || fail 'Install quickshell to show the keybindings overlay.'
command -v flock >/dev/null || fail 'flock is required for the keybindings overlay.'
mkdir -p "$cache_dir" || fail "Cannot create $cache_dir for the keybindings overlay."
exec 9>"$cache_dir/launch.lock" || fail "Cannot open the keybindings overlay lock in $cache_dir."
flock -w 10 9 || fail 'The keybindings overlay is still starting; try again.'
entry="$config_dir/quickshell/keybinds-overlay/shell.qml"
ipc() { qs -p "$entry" ipc call keybinds "$1" 9>&-; }
if ipc toggle >/dev/null 2>&1; then exit 0; fi
# shellcheck source=scripts/theming/palette.sh
source "$config_dir/scripts/theming/palette.sh" || fail 'Cannot load the theme palette for the keybindings overlay.'
declare -a wal
wal_load
# shellcheck disable=SC2034  # read by role_load, wal_role and wal_render
declare -A role=()
role_load
export KEYBINDS_BACKGROUND="${wal[0]}"
export KEYBINDS_ACCENT
KEYBINDS_ACCENT=$(wal_role primary)
export KEYBINDS_FOREGROUND
KEYBINDS_FOREGROUND=$(wal_readable_on "${wal[0]}")
export KEYBINDS_FONT
KEYBINDS_FONT=$(head -n1 "$config_dir/options/font" 2>/dev/null || true)
qs -p "$entry" --no-duplicate --daemonize >"$cache_dir/session.log" 2>&1 9>&- \
    || fail "The keybindings overlay failed to start; see $cache_dir/session.log"
# Hold the lock until IPC answers, so a quick second Super+H toggles this
# instance closed instead of racing a second start.
for ((attempt = 0; attempt < 60; attempt++)); do
    if ipc ping >/dev/null 2>&1; then exit 0; fi
    sleep 0.05
done
fail "The keybindings overlay did not answer; see $cache_dir/session.log"
