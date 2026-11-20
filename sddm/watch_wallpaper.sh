#!/bin/bash
#
# SDDM Wallpaper Sync Script
# Watches for awww wallpaper changes and updates SDDM automatically
# awww cache layout: ~/.cache/awww/<version>/<monitor>
#

# shellcheck source=scripts/lib/wallpaper.sh
. "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib/wallpaper.sh"
cache_dir="$HOME/.cache/awww"
update_script="$(dirname "${BASH_SOURCE[0]}")/update_sddm.sh"

# Ensure the cache dir exists
mkdir -p "$cache_dir"

# Function to update SDDM wallpaper
update_sddm() {
    if [[ -f "$update_script" ]]; then
        "$update_script" >/dev/null \
            2> >(logger -t sddm-wallpaper-sync) &
    fi
}

# Initial update
update_sddm

# Watch for changes to the monitor's cache file (recursive: version subdir may not exist yet).
# close_write alone: awww rewrites the entry in place, so modify would start a
# second conversion for the same image. The monitor preference is read per
# event, so a change in the settings panel takes effect without a restart.
command -v inotifywait >/dev/null 2>&1 || { echo "watch_wallpaper: inotifywait (inotify-tools) is required" >&2; exit 1; }
inotifywait -m -r -e close_write --format '%f' "$cache_dir" 2>/dev/null | while read -r file; do
    monitor=$(wallpaper_main_monitor)
    # With no preference set, any monitor's cache entry is a real change.
    [[ -z "$monitor" || "$file" == "$monitor" ]] || continue
    update_sddm
done
