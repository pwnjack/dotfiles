#!/bin/bash
# Click on Waybar's custom/updates: toggle the update card. The update itself
# is scripts/updates/updates-run.sh and outlives the card.
set -euo pipefail
[[ $# -eq 0 ]] || { echo 'Usage: updates-popover.sh' >&2; exit 2; }
# shellcheck source=scripts/lib/qs-launch.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/qs-launch.sh"
qs_launch updates updates Updates 'the update card'
if qs_ipc toggle >/dev/null 2>&1; then exit 0; fi
qs_theme UPDATES
export UPDATES_CURSOR_X UPDATES_BAR_POSITION
# Waybar does not say where on the module the click landed; the cursor does.
UPDATES_CURSOR_X=$(hyprctl cursorpos -j 2>/dev/null | jq -r '.x // -1' 2>/dev/null || echo -1)
UPDATES_BAR_POSITION=$(qs_option bar-position top)
qs_start
