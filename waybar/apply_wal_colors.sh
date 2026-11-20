#!/bin/bash
#
# Render the matugen palette as GTK CSS color definitions.
#
# waybar/style.css and swaync/style.css both import the file written here.
# Render only the names their stylesheets read (test-theming.sh checks the
# set), with defaults on a fresh checkout where matugen has never run.
#
# Waybar restyles itself when this file changes (reload_style_on_change in
# waybar/config.jsonc); no reload is sent, because a full one rebuilds the bar
# and briefly resizes every tiled window.
#

set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/wal"

declare -a wal=()
# shellcheck source=scripts/theming/palette.sh
. "$config_dir/scripts/theming/palette.sh"
wal_load
# shellcheck disable=SC2034  # read by role_load and wal_role
declare -A role=()
role_load

mkdir -p "$cache_dir"

# Replaced only when it differs: Waybar watches this file, so a truncating
# write could be read half-written, and a second render in the same fan-out
# (swaync's script runs this first) must not restyle the bar again.
{
    echo "@define-color foreground ${wal[7]};"
    echo "@define-color background ${wal[0]};"
    echo "@define-color color8 ${wal[8]};"
    echo "@define-color accent $(wal_role primary);"
    for name in surface_container secondary_container on_secondary_container error; do
        echo "@define-color $name $(wal_role "$name");"
    done
} | wal_write "$cache_dir/colors-waybar.css"
[ $? -lt 2 ] || exit 1   # 1 means unchanged
