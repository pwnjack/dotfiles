#!/bin/bash
#
# Wallpaper Restore (run at Hyprland startup, after awww-daemon)
# Re-applies the last wallpaper: waypaper config first, then awww cache.
#

sleep 0.5

# 0. Random wallpaper on startup (options/randomwallpaper = enabled)
#    waypaper --random also runs its post_command (wall.sh), so palette colours follow
if grep -q "enabled" "$HOME/.config/options/randomwallpaper" 2>/dev/null \
    && command -v waypaper >/dev/null 2>&1; then
    waypaper --random
    exit 0
fi

# 1. Wallpaper saved by waypaper
wp=$(grep "^wallpaper = " "$HOME/.config/waypaper/config.ini" 2>/dev/null \
    | sed "s/^wallpaper = //" | sed "s|^~|$HOME|")
if [ -f "$wp" ]; then
    awww img "$wp"
    exit 0
fi

# 2. Last wallpaper recorded in the awww cache for the main monitor, or for
#    any monitor when there is no preference.
# shellcheck source=scripts/lib/wallpaper.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/wallpaper.sh"
wp=$(wallpaper_from_cache "$HOME/.cache/awww")
[ -f "$wp" ] && awww img "$wp" && exit 0

# 3. Fall back to the current-wallpaper symlink (fresh installs)
wp=$(readlink -f "$HOME/.config/options/wallpaper" 2>/dev/null)
[ -f "$wp" ] && awww img "$wp"
