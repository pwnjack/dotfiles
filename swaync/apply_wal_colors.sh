#!/bin/bash
#
# Reload SwayNC's styles after a palette change.
#
# swaync/style.css imports ~/.cache/wal/colors-waybar.css, which
# waybar/apply_wal_colors.sh renders. The driver runs the component scripts in
# name order, swaync before waybar, so that file is rendered here first (the
# renderer is idempotent and cheap) and the reload sees the new palette.
#
set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
bash "$config_dir/waybar/apply_wal_colors.sh" || exit 1

# The reload is a D-Bus call that a stuck daemon could hold for the bus default
# of 25 s; the fan-out runs the components in sequence, so bound it.
if pgrep -x swaync >/dev/null; then
    timeout 5 swaync-client -rs >/dev/null 2>&1 || true
fi
