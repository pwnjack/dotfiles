#!/bin/bash
#
# Register Strata's embedded FileChooser portal for options/filemanager.
# hyprland-portals.conf prefers it, with GTK as the fallback when absent.
# Run by install.sh and the settings panel. Only our registrations are removed
# when another file manager is selected; reload the bus and portal on change.
# Dismiss Strata's in-app offer whenever its installed binary is safe, even
# with another manager selected: accepting it rewrites hyprland-portals.conf.
# Idempotent; always exits 0, since GTK can still provide a file chooser.

set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
name=org.freedesktop.impl.portal.desktop.strata
portal="$data_dir/xdg-desktop-portal/portals/strata.portal"
service="$data_dir/dbus-1/services/$name.service"

fm=""
{ read -r fm < "$config_dir/options/filemanager"; } 2>/dev/null
read -r fm _ <<< "$fm"   # the binary is the first word; ignore option arguments
fm="${fm:-strata}"

binary=""
binary=$(command -v strata 2>/dev/null) || binary=""
[ -z "$binary" ] || binary=$(readlink -f -- "$binary" 2>/dev/null) || binary=""
# D-Bus Exec is not a shell command: Strata rejects quoting and whitespace.
case "$binary" in
    *[[:space:]\"\'\\]*|"") binary="" ;;
esac
[[ "$binary" = /* && -f "$binary" && -x "$binary" ]] || binary=""

# Strata requires every canonical path component, including the executable,
# to be owned by root or this user and not writable by group or others.
safe_path() {
    local component="$1" owner mode metadata uid
    uid=$(id -u) || return 1
    while :; do
        metadata=$(stat -c '%u %a' -- "$component" 2>/dev/null) || return 1
        read -r owner mode <<< "$metadata"
        [[ "$owner" = 0 || "$owner" = "$uid" ]] || return 1
        [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
        (( (8#$mode & 0022) == 0 )) || return 1
        [ "$component" != / ] || break
        component="${component%/*}"
        component="${component:-/}"
    done
}
[ -z "$binary" ] || safe_path "$binary" || binary=""

selected=0
if [ -n "$binary" ]; then
    "$binary" --dismiss-portal-prompt >/dev/null 2>&1 || true
    choice=$(command -v -- "$fm" 2>/dev/null) || choice=""
    [ -z "$choice" ] || choice=$(readlink -f -- "$choice" 2>/dev/null) || choice=""
    if [ "${fm##*/}" = strata ] || [ "$choice" = "$binary" ]; then
        selected=1
    fi
fi

changed=0
write_file() {
    local target="$1" content="$2" temporary
    if [ -L "$target" ] || ! cmp -s -- "$target" <(printf '%s\n' "$content"); then
        mkdir -p -- "${target%/*}" || return 1
        temporary=$(mktemp "${target%/*}/.strata.XXXXXX") || return 1
        if printf '%s\n' "$content" > "$temporary" && mv -fT -- "$temporary" "$target"; then
            changed=1
        else
            rm -f -- "$temporary"
            return 1
        fi
    fi
}

if [ "$selected" = 1 ]; then
    write_file "$portal" "[portal]
DBusName=$name
Interfaces=org.freedesktop.impl.portal.FileChooser;"
    write_file "$service" "[D-BUS Service]
Name=$name
Exec=$binary --portal"
else
    if [ -f "$portal" ] && grep -qxF "DBusName=$name" "$portal"; then
        rm -f -- "$portal" && changed=1
    fi
    if [ -f "$service" ] && grep -qxF "Name=$name" "$service"; then
        rm -f -- "$service" && changed=1
    fi
fi

if [ "$changed" = 1 ]; then
    if command -v busctl >/dev/null 2>&1; then
        busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
            org.freedesktop.DBus ReloadConfig >/dev/null 2>&1 || true
    fi
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user try-restart xdg-desktop-portal.service >/dev/null 2>&1 || true
    fi
fi

exit 0
