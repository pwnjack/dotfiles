#!/bin/bash
#
# Files derived from options, rendered after every overlay sync (overlay.sh
# runs this inside its lock): each step writes only into ~/.local/state, where
# a tracked symlink points, and always leaves its output existing.
#
#   derived.sh <config dir>
set -uo pipefail
config_dir=${1:?usage: derived.sh <config dir>}
status=0

# Font includes for rofi, Waybar and Ghostty (tracked symlinks point at them).
# The script is absent only in isolated test fixtures.
if [ -f "$config_dir/scripts/fonts/apply-font.sh" ]; then
    bash "$config_dir/scripts/fonts/apply-font.sh" --includes >/dev/null || status=1
fi
exit "$status"
