#!/bin/bash
#
# Which wallpaper is "the current one". Sourced, never executed.
#
# With several monitors, the answer is the image on options/mainmonitor; an
# empty preference means "no preference", and the first monitor awww reports
# wins. wall.sh, carousel-state.sh, restore-wallpaper.sh and the SDDM watcher
# all use these, so they cannot disagree about which image the palette,
# carousel, login restore and greeter follow.
#
# sddm/update_sddm_root.sh deliberately keeps its own copy: it runs as root and
# must never source a file the user can edit.
#

# shellcheck source=scripts/lib/options.sh
. "${BASH_SOURCE[0]%/*}/options.sh"

# wallpaper_main_monitor -> the preferred connector, or nothing.
#
# Every function here returns 0 when there is simply nothing to report, so a
# caller running under `set -e` does not abort on an empty answer.
wallpaper_main_monitor() {
    option "${XDG_CONFIG_HOME:-$HOME/.config}/options/mainmonitor"
}

# wallpaper_record <image> — publish <image> as the current wallpaper: the
# ~/.cache/current_wallpaper link (options/wallpaper points at it) and Rofi's
# background include. wall.sh and install.sh both go through this, so the two
# writers cannot drift.
wallpaper_record() {
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}" escaped
    ln -sfn "$1" "$cache_dir/current_wallpaper" || return 1
    escaped=${1//\\/\\\\}
    escaped=${escaped//\"/\\\"}
    mkdir -p "$cache_dir/wal" || return 1
    printf '* { wallpaper: url("%s", width); }\n' "$escaped" > "$cache_dir/wal/rofi-wallpaper.rasi"
}

# wallpaper_from_query <awww-query-output> -> image path, empty when none.
#
# awww query prints one line per monitor: ": DP-1: 2560x1440, ... image: /path".
wallpaper_from_query() {
    local monitor line first=""
    monitor=$(wallpaper_main_monitor)
    while IFS= read -r line; do
        [[ "$line" == *"image: "* ]] || continue
        if [ -n "$monitor" ] && [[ "$line" == ": $monitor:"* ]]; then
            printf '%s' "${line#*image: }"
            return 0
        fi
        [ -n "$first" ] || first=${line#*image: }
    done <<< "$1"
    printf '%s' "$first"
}

# wallpaper_from_cache <awww-cache-dir> -> image path, empty when none.
#
# awww keeps <cache-dir>/<version>/<monitor> files ending in the image path.
# The newest file for the preferred monitor (or any monitor) wins; this is what
# survives a restart, when awww itself cannot be queried yet.
#
# awww 0.12 separates the fields with NUL bytes, so grep needs -a: without it
# grep prints "binary file matches" instead of the path. Older releases used
# spaces; the same pattern reads both.
#
# Only an entry naming an existing file counts. Animated wallpapers add a
# frame-cache file beside the per-monitor entries, and reading it with -a
# yields binary garbage rather than a path.
wallpaper_from_cache() {
    local monitor file path newest="" best=""
    local -a files
    monitor=$(wallpaper_main_monitor)
    if [ -n "$monitor" ]; then
        files=("$1"/*/"$monitor")
    else
        files=("$1"/*/*)
    fi
    for file in "${files[@]}"; do
        [ -f "$file" ] || continue
        [ -z "$newest" ] || [ "$file" -nt "$newest" ] || continue
        path=$(grep -aoE '/.+$' "$file" 2>/dev/null | tr -d '\0')
        [[ "$path" != *$'\n'* && -f "$path" ]] || continue
        newest=$file
        best=$path
    done
    printf '%s' "$best"
}
