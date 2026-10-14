#!/bin/bash
#
# Render the shared matugen palette in both formats used under hypr/:
#
#   colors.lua   -> Hyprland 0.55+
#   colors.conf  -> hyprlock (which still uses Hyprlang)
#
# Both tracked paths are symlinks into ~/.cache/wal. Producing both files here
# keeps a fresh checkout valid even when matugen itself is not installed yet.

set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/wal"

declare -a wal=()
# shellcheck source=scripts/theming/palette.sh
# shellcheck disable=SC1091
. "$config_dir/scripts/theming/palette.sh"
wal_load

mkdir -p "$cache_dir"

foreground="${wal[7]#\#}"
background="${wal[0]#\#}"

{
    printf '%s = rgba(%sCC)\n' '$foreground' "$foreground"
    printf '%s = rgb(%s)\n\n' '$foregroundfull' "$foreground"
    printf '%s = rgba(%sCC)\n' '$background' "$background"
    printf '%s = rgb(%s)\n' '$backgroundfull' "$background"
} > "$cache_dir/colors-hyprland.conf" || exit 1

{
    echo 'return {'
    printf '    foreground = "rgba(%sCC)",\n' "$foreground"
    printf '    foreground_full = "rgb(%s)",\n' "$foreground"
    printf '    background = "rgba(%sCC)",\n' "$background"
    printf '    background_full = "rgb(%s)",\n' "$background"
    echo '}'
} > "$cache_dir/colors-hyprland.lua" || exit 1

# A running Lua-configured Hyprland picks up the new module on reload. During
# the one-time migration from Hyprlang, Hyprland intentionally stays on the
# language it started with until the next session, so this is harmless there.
if command -v hyprctl >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 || true
fi

exit 0
