#!/bin/bash
# Click on Waybar's volume icon: toggle the sound popover. Nothing of it runs
# while it is closed.
set -euo pipefail
[[ $# -eq 0 ]] || { echo 'Usage: sound-popover.sh' >&2; exit 2; }
# shellcheck source=scripts/lib/qs-launch.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/qs-launch.sh"
qs_launch sound sound Sound 'the sound popover'
for binary in hyprctl jq; do
    command -v "$binary" >/dev/null 2>&1 || qs_fail "$binary is required for the sound popover."
done
if qs_ipc toggle >/dev/null 2>&1; then exit 0; fi
qs_theme SOUND
export SOUND_CURSOR_X SOUND_BAR_POSITION
# Waybar does not say where on the module the click landed; the cursor does.
SOUND_CURSOR_X=$(hyprctl cursorpos -j 2>/dev/null | jq -r '.x // -1' 2>/dev/null || echo -1)
SOUND_BAR_POSITION=$(qs_option bar-position top)
qs_start
