#!/bin/bash
#
# Wallpaper Restore (run at Hyprland startup, after awww-daemon)
# Re-applies the last wallpaper: a random one when options/randomwallpaper says
# so, else waypaper's saved image, else the awww cache, else the current-wallpaper
# symlink. Each source is tried only when the one before it failed, so a
# transient failure (awww not ready yet) falls through instead of ending here.
#

sleep 0.5

# shellcheck source=scripts/lib/options.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/options.sh"

# 0. Random wallpaper on startup (options/randomwallpaper = enabled)
#    waypaper --random also runs its post_command (wall.sh), so palette colours follow
if [ "$(option "$HOME/.config/options/randomwallpaper")" = enabled ] \
    && command -v waypaper >/dev/null 2>&1; then
    waypaper --random && exit 0
fi

# 1. Wallpaper saved by waypaper
wp=$(grep "^wallpaper = " "$HOME/.config/waypaper/config.ini" 2>/dev/null \
    | sed "s/^wallpaper = //" | sed "s|^~|$HOME|")
[ -f "$wp" ] && awww img "$wp" && exit 0

# 2. Last wallpaper recorded in the awww cache for the main monitor, or for
#    any monitor when there is no preference.
# shellcheck source=scripts/lib/wallpaper.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/wallpaper.sh"
wp=$(wallpaper_from_cache "$HOME/.cache/awww")
[ -f "$wp" ] && awww img "$wp" && exit 0

# 3. Fall back to the current-wallpaper symlink (fresh installs)
wp=$(readlink -f "$HOME/.config/options/wallpaper" 2>/dev/null)
[ -f "$wp" ] && awww img "$wp"
