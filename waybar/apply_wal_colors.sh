#!/bin/bash
#
# Render the matugen palette as GTK CSS color definitions.
#
# waybar/style.css and swaync/style.css both import the file written here.
# Render the ANSI slots and semantic accent, surface, selection and error
# roles, with defaults on a fresh checkout where matugen has never run.
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
# shellcheck disable=SC2034  # read by role_load, wal_role and wal_render
declare -A role=()
role_load

mkdir -p "$cache_dir"

{
    echo "@define-color foreground ${wal[7]};"
    echo "@define-color background ${wal[0]};"
    echo "@define-color cursor ${wal[7]};"
    echo
    for i in "${!wal[@]}"; do
        echo "@define-color color$i ${wal[$i]};"
    done
    echo "@define-color accent $(wal_role primary);"
    echo "@define-color on_accent $(wal_role on_primary);"
    for name in surface_container surface_container_high secondary_container on_secondary_container error on_error; do
        echo "@define-color $name $(wal_role "$name");"
    done
} > "$cache_dir/colors-waybar.css"
