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
qs_anchor UPDATES
qs_start
