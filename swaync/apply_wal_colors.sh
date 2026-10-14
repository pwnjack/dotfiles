#!/bin/bash
#
# SwayNC Matugen Color Integration
# Reloads SwayNC styles after matugen regenerates colors
#
# SwayNC's style.css imports ~/.cache/wal/colors-waybar.css directly,
# so we just need to trigger a style reload after matugen updates that file.
#

# Reload SwayNC styles to pick up new matugen colors
if pgrep -x swaync > /dev/null; then
    swaync-client -rs
fi
