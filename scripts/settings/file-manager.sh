#!/bin/bash
#
# Make the configured file manager (options/filemanager) the one that answers
# org.freedesktop.FileManager1, the D-Bus service behind every "Show in folder":
# the capture toasts, browser downloads, portals.
#
# Several installed file managers can claim that name (Nautilus, Dolphin,
# Thunar each ship a service file for it) and D-Bus then picks one on its own,
# whatever the preference says. A user service file takes precedence over the
# system ones, so this copies the configured file manager's own service file to
# ${XDG_DATA_HOME:-~/.local/share}/dbus-1/services/ and asks the bus to reload.
# A file manager with no such service (yazi, a TUI) removes the copy, which
# leaves the system's choice.
#
# Run by install.sh and by the settings panel when the File manager row
# changes. Idempotent; always exits 0, because a missing D-Bus service only
# costs "Show in folder" its selection.

set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
name=org.freedesktop.FileManager1
target="${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services/$name.service"

fm=""
{ read -r fm < "$config_dir/options/filemanager"; } 2>/dev/null
read -r fm _ <<< "$fm"   # the binary is the first word; the option may carry arguments
fm="${fm:-strata}"

IFS=: read -ra data_dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

source_file=""
if binary=$(command -v -- "$fm" 2>/dev/null) && [ -n "$binary" ]; then
    binary=$(readlink -f -- "$binary")
    for dir in "${data_dirs[@]}"; do
        for file in "$dir"/dbus-1/services/*.service; do
            [ -f "$file" ] || continue
            grep -qx "Name=$name" "$file" || continue
            exec_line=$(sed -n 's/^Exec=//p' "$file" | head -n 1)
            [ "$(readlink -f -- "${exec_line%% *}")" = "$binary" ] || continue
            source_file=$file
            break 2
        done
    done
fi

changed=0
if [ -n "$source_file" ]; then
    if ! cmp -s -- "$source_file" "$target"; then
        mkdir -p -- "${target%/*}" && cp -- "$source_file" "$target" && changed=1
    fi
elif [ -e "$target" ]; then
    # Only a copy this script made goes: one identical to a system service file
    # for the name. An override written by hand or by another tool stays.
    for dir in "${data_dirs[@]}"; do
        for file in "$dir"/dbus-1/services/*.service; do
            [ -f "$file" ] || continue
            grep -qx "Name=$name" "$file" || continue
            if cmp -s -- "$file" "$target"; then
                rm -f -- "$target" && changed=1
                break 2
            fi
        done
    done
fi

# The bus reads service files at start-up and on ReloadConfig only.
if [ "$changed" = 1 ] && command -v busctl >/dev/null 2>&1; then
    busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus ReloadConfig >/dev/null 2>&1 || true
fi

exit 0
