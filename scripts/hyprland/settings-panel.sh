#!/bin/bash
# A settings window has no work to do between visits: launch on demand, exit on close.
set -euo pipefail
config_dir="$HOME/.config"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/settings-panel"
for binary in qs gjs flock; do
    command -v "$binary" >/dev/null || { echo "$binary is required for the settings panel" >&2; exit 1; }
done
page="${1:-}"
[[ -z $page || $page =~ ^[a-z]+$ ]] || { echo "Unknown settings page: $page" >&2; exit 2; }
mkdir -p "$cache_dir"
exec 9>"$cache_dir/launch.lock"
flock -w 10 9 || exit 1
entry="$config_dir/quickshell/settings-panel/shell.qml"
if [[ -n $page ]]; then
    if qs -p "$entry" ipc call settings open "$page" >/dev/null 2>&1 9>&-; then exit 0; fi
elif qs -p "$entry" ipc call settings toggle >/dev/null 2>&1 9>&-; then exit 0; fi
export SETTINGS_PAGE="$page"
# shellcheck source=scripts/theming/palette.sh
source "$config_dir/scripts/theming/palette.sh"
declare -a wal
wal_load
# shellcheck disable=SC2034  # read by role_load, wal_role and wal_render
declare -A role=()
role_load
export SETTINGS_BACKGROUND="${wal[0]}"
export SETTINGS_FOREGROUND
SETTINGS_FOREGROUND=$(wal_readable_on "${wal[0]}")
export SETTINGS_ACCENT
SETTINGS_ACCENT=$(wal_role primary)
export SETTINGS_ON_ACCENT
SETTINGS_ON_ACCENT=$(wal_role on_primary)
export SETTINGS_STARTED_MS
SETTINGS_STARTED_MS=$(date +%s%3N)
qs -p "$entry" --no-duplicate --daemonize >"$cache_dir/session.log" 2>&1 9>&-
