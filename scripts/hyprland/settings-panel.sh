#!/bin/bash
# A settings window has no work to do between visits: launch on demand, exit on close.
set -euo pipefail
page="${1:-}"
[[ -z $page || $page =~ ^[a-z]+$ ]] || { echo "Unknown settings page: $page" >&2; exit 2; }
# shellcheck source=scripts/lib/qs-launch.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/qs-launch.sh"
qs_launch settings-panel settings Settings 'the settings panel'
command -v gjs >/dev/null 2>&1 || qs_fail 'gjs is required for the settings panel.'
if [[ -n $page ]]; then
    if qs_ipc open "$page" >/dev/null 2>&1; then exit 0; fi
elif qs_ipc toggle >/dev/null 2>&1; then exit 0; fi
export SETTINGS_PAGE="$page"
qs_theme SETTINGS error
export SETTINGS_STARTED_MS
SETTINGS_STARTED_MS=$(date +%s%3N)
qs_start
