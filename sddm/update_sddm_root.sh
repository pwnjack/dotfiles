#!/bin/bash
#
# SDDM Wallpaper Updater (root side)
# Runs as root via sudo (see setup-sudo.sh) or a systemd service.
# Converts the user's current wallpaper into the SDDM theme background.
#
# Usage: update_sddm_root.sh [username]
#   The user defaults to $SUDO_USER, then the first regular user (uid 1000).
#

TARGET_USER="${1:-${SUDO_USER:-$(id -un 1000 2>/dev/null)}}"
USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
RUNUSER=/usr/bin/runuser
LOCK_FILE=/run/lock/sddm-wallpaper.lock

if [[ -z "$USER_HOME" ]]; then
    echo "Error: could not resolve home directory for user '$TARGET_USER'" >&2
    exit 1
fi

if [[ ! -x "$RUNUSER" ]]; then
    echo "Error: runuser is required to decode the SDDM wallpaper without root privileges" >&2
    exit 1
fi

# One update at a time, from discovery to publication: the watcher starts a
# helper per cache write, so two helpers would otherwise resolve different
# images and the one that finishes last would publish the older one, or sweep
# the other's temporary file. /run/lock is root-only, so no user can plant the
# lock file.
exec 8>"$LOCK_FILE" || exit 1
flock 8

# awww cache layout: ~/.cache/awww/<version>/<monitor>, ending in the image
# path. awww 0.12 separates the fields with NUL bytes, so grep needs -a (without
# it grep prints "binary file matches" and the path is never found); older
# releases used spaces, and the same pattern reads both.
#
# This lookup duplicates scripts/lib/wallpaper.sh, deliberately. THIS script
# runs as root against another user's home, so sourcing a shared helper out of
# a user-writable $USER_HOME/.config/scripts/ would hand that user a root shell.
if ! wallpaper=$("$RUNUSER" -u "$TARGET_USER" -- /bin/bash -c '
    user_home=$1
    [[ -d "$user_home" ]] || exit 10

    # Empty preference means "no preference": consider every monitor instead
    # of guessing a connector name. The newest entry that names an existing
    # file wins, so the frame-cache file of an animated wallpaper (binary, not a
    # path) cannot shadow a real entry. This whole block is single-quoted, so
    # it uses double quotes only.
    monitor=$(cat "$user_home/.config/options/mainmonitor" 2>/dev/null)
    if [[ -n "$monitor" ]]; then
        files=("$user_home/.cache/awww/"*/"$monitor")
    else
        files=("$user_home/.cache/awww/"*/*)
    fi
    wallpaper="" newest=""
    for file in "${files[@]}"; do
        [[ -f "$file" ]] || continue
        [[ -z "$newest" || "$file" -nt "$newest" ]] || continue
        path=$(grep -aoE "/.+\$" "$file" 2>/dev/null | tr -d "\000")
        [[ -f "$path" && "$path" != *[[:cntrl:]]* ]] || continue
        newest=$file
        wallpaper=$path
    done

    # Fallback: the current-wallpaper symlink maintained by wall.sh.
    if [[ -z "$wallpaper" ]] || [[ ! -f "$wallpaper" ]]; then
        wallpaper=$(readlink -f "$user_home/.config/options/wallpaper" 2>/dev/null)
    fi
    [[ -n "$wallpaper" ]] && [[ -f "$wallpaper" ]] && printf "%s\n" "$wallpaper"
' _ "$USER_HOME"); then
    echo "Error: could not resolve home directory for user '$TARGET_USER'" >&2
    exit 1
fi

if [[ -z "$wallpaper" ]]; then
    exit 0
fi

if ! "$RUNUSER" -u "$TARGET_USER" -- \
     /bin/bash -c 'command -v ffmpeg >/dev/null'; then
    echo "Error: ffmpeg is required but not installed" >&2
    exit 1
fi

# Determine which SDDM theme is in use (default: sddm-astronaut-theme): the
# Current key anywhere in the [Theme] section. The doctor's check_sddm parses
# it the same way; keep the two in step.
current_theme=""
if [[ -f /etc/sddm.conf ]]; then
    current_theme=$(awk '/^\[/ { theme = ($0 == "[Theme]") } theme && /^[ \t]*Current[ \t]*=/ { sub(/^[^=]*=[ \t]*/, ""); sub(/[ \t]+$/, ""); print; exit }' /etc/sddm.conf 2>/dev/null)
fi
[[ -z "$current_theme" ]] && current_theme="sddm-astronaut-theme"

themes_to_update=("$current_theme")
[[ "$current_theme" != "sddm-astronaut-theme" ]] && themes_to_update+=("sddm-astronaut-theme")

# root_only_dir <dir> — a directory root owns and nobody else may write to, so
# no other user can swap its entries while root writes there.
root_only_dir() {
    local meta
    meta=$(stat -c '%u %a' -- "$1" 2>/dev/null) || return 1
    [[ -d "$1" && "$meta" =~ ^0\ [0-7]?[0-7][0145][0145]$ ]]
}

temporary=""
cleanup_temporary() {
    if [[ -n "$temporary" ]]; then
        rm -f -- "$temporary"
        temporary=""
    fi
}

updated=false
for theme in "${themes_to_update[@]}"; do
    theme_dir="/usr/share/sddm/themes/$theme"
    resolved_theme_dir=$(readlink -f -- "$theme_dir" 2>/dev/null)
    [[ -n "$resolved_theme_dir" ]] && [[ -d "$resolved_theme_dir" ]] || continue
    if ! root_only_dir "$resolved_theme_dir"; then
        echo "Error: refusing SDDM theme '$theme': resolved theme directory is not root-owned or is writable by others" >&2
        continue
    fi

    backgrounds_path="$resolved_theme_dir/Backgrounds"
    if [[ -e "$backgrounds_path" ]] || [[ -L "$backgrounds_path" ]]; then
        backgrounds_dir=$(readlink -f -- "$backgrounds_path" 2>/dev/null)
    else
        if ! mkdir -- "$backgrounds_path"; then
            echo "Error: could not create the Backgrounds directory for SDDM theme '$theme'" >&2
            continue
        fi
        backgrounds_dir=$(readlink -f -- "$backgrounds_path" 2>/dev/null)
    fi
    if [[ -z "$backgrounds_dir" ]] || ! root_only_dir "$backgrounds_dir"; then
        echo "Error: refusing SDDM theme '$theme': resolved Backgrounds directory is not root-owned or is writable by others" >&2
        continue
    fi

    destination="$backgrounds_dir/wallpaper.jpg"
    for stale_temporary in "$backgrounds_dir"/.wallpaper.jpg.*; do
        [[ -e "$stale_temporary" ]] || [[ -L "$stale_temporary" ]] || continue
        rm -f -- "$stale_temporary"
    done

    temporary=$(mktemp "$backgrounds_dir/.wallpaper.jpg.XXXXXX") || continue
    trap cleanup_temporary EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    if "$RUNUSER" -u "$TARGET_USER" -- \
       ffmpeg -i "$wallpaper" -frames:v 1 -f mjpeg - > "$temporary" 2>/dev/null &&
       [[ -s "$temporary" ]] && chmod 0644 -- "$temporary"; then
        if mv -f -- "$temporary" "$destination"; then
            temporary=""
            # The exit status reports the active theme; the astronaut fallback
            # is kept in step when present but its success alone is not one.
            [[ "$theme" == "$current_theme" ]] && updated=true
        fi
    fi
    cleanup_temporary
    trap - EXIT INT TERM
done

if ! $updated; then
    echo "Error: the active SDDM theme '$current_theme' was not updated" >&2
    exit 1
fi
exit 0
