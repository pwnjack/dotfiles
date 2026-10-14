#!/bin/bash
#
# Render the matugen palette as a ghostty color include.
#
# ghostty/config pulls it in with `config-file = ?colors` (the AI sidebar
# inherits it, since ghostty loads that file first), and ghostty/colors is a
# tracked symlink to the file written here. Rendering from the shared loader keeps it complete on a fresh
# checkout, before matugen has ever run.
#

set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/wal"

declare -a wal=()
# shellcheck source=scripts/theming/palette.sh
. "$config_dir/scripts/theming/palette.sh"
wal_load

mkdir -p "$cache_dir"

{
    echo "# Automatically generated from the matugen palette - do not edit manually"
    echo
    echo "background = ${wal[0]}"
    echo "foreground = ${wal[7]}"
    echo "cursor-color = ${wal[7]}"
    echo
    for i in "${!wal[@]}"; do
        echo "palette = $i=${wal[$i]}"
    done
} > "$cache_dir/ghostty-colors" || exit 1

# Reload running ghostty so its configured palette is the new one.
pkill -USR2 -x ghostty 2>/dev/null

# Clear old OSC palette, foreground, background and cursor overrides so
# open terminals use their configured colours. Bound each write: a stuck pty
# must not stall wallpaper changes. Tests point WAL_PTS_DIR at fake ptys.
pts_dir="${WAL_PTS_DIR:-/dev/pts}"
for pty in "$pts_dir"/[0-9]*; do
    [ -O "$pty" ] && [ -w "$pty" ] || continue
    timeout 1 sh -c 'printf "\033]104\033\134\033]110\033\134\033]111\033\134\033]112\033\134" > "$1"' _ "$pty" 2>/dev/null || true
done

exit 0
