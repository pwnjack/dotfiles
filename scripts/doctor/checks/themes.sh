#!/bin/bash
#
# Themes the dotfiles select but the machine may lack: the GTK theme, icon
# theme and cursor theme, and the Kvantum theme. Each has been missing on a
# machine whose binaries and plugins all resolved, and the symptom is silent:
# GTK falls back to Adwaita, icons to hicolor, the cursor to the default.
#
# Selections are read from tracked files: gtk-theme-name, gtk-icon-theme-name
# and gtk-cursor-theme-name in every defaults/gtk-*/settings.ini, icon_theme in
# every defaults/qt*ct/qt*ct.conf, and defaults/options/cursortheme. Each is
# read from the live file the overlay renders from that default, or from the
# default when nothing is rendered yet. The Kvantum theme has no tracked
# default (the settings panel writes Kvantum/kvantum.kvconfig), so only that
# live file is read, and nothing is checked while it is absent.
#
# GTK, icon and cursor selections are also read from gsettings
# (org.gnome.desktop.interface), which GTK prefers over settings.ini on Wayland.
#
# Themes are looked up where the toolkits look: ~/.themes and themes/ under
# $XDG_DATA_HOME and every $XDG_DATA_DIRS entry for GTK; ~/.icons and icons/
# under the same for icons and cursors (a cursor theme may only inherit one that
# has cursors); Kvantum/ under $XDG_CONFIG_HOME and the data dirs for Kvantum,
# plus a Kvantum theme bundled in a GTK theme folder.
#
# Severity is WARN: the session starts and looks wrong, nothing breaks.
#
# Accepted risk: a GTK theme counts as installed when it has a gtk-3.0 or a
# gtk-4.0 directory, so one that ships only the other major version is not
# reported, and GTK's built-in themes are not looked up.

# _thm_cursor <depth> <name> <dir>... -- a cursor theme is in one of the icon
# dirs, directly or through index.theme's Inherits= (capped, so a cycle ends).
_thm_cursor() {
    local depth="$1" name="$2" dir parent inherits
    local -a parents
    shift 2
    for dir; do [ -d "$dir/$name/cursors" ] && return 0; done
    [ "$depth" -lt 5 ] || return 1
    for dir; do
        [ -f "$dir/$name/index.theme" ] || continue
        inherits="$(_thm_ini "$dir/$name/index.theme" 'Icon Theme' Inherits)"
        IFS=, read -ra parents <<< "$inherits"
        for parent in "${parents[@]}"; do
            parent="${parent#"${parent%%[![:space:]]*}"}"
            parent="${parent%"${parent##*[![:space:]]}"}"
            case "$parent" in '' | */*) continue ;; esac
            _thm_cursor $((depth + 1)) "$parent" "$@" && return 0
        done
        return 1
    done
    return 1
}

# _thm_present <kind> <name> -- host probe: the theme is installed. Kind is gtk,
# icon, cursor or kvantum. DOCTOR_THEME_HOME stands in for $HOME (and so for the
# XDG_*_HOME dirs) and DOCTOR_THEME_SHARE for the $XDG_DATA_DIRS list, so a test
# can aim the lookup at a fixture.
_thm_present() {
    local home="${DOCTOR_THEME_HOME:-$HOME}" data_home config_home dir base
    local -a shares roots gtk_dirs dirs
    if [ -n "${DOCTOR_THEME_HOME:-}" ]; then
        data_home="$home/.local/share" config_home="$home/.config"
    else
        data_home="${XDG_DATA_HOME:-$home/.local/share}" config_home="${XDG_CONFIG_HOME:-$home/.config}"
    fi
    IFS=: read -ra shares <<< "${DOCTOR_THEME_SHARE:-${XDG_DATA_DIRS:-/usr/local/share:/usr/share}}"
    roots=("$data_home" "${shares[@]}")
    case "$2" in
        */*) return 1 ;;
    esac
    gtk_dirs=("$home/.themes")
    for dir in "${roots[@]}"; do gtk_dirs+=("$dir/themes"); done
    case "$1" in
        gtk)
            case "$2" in
                Adwaita|Adwaita-dark|HighContrast|HighContrastInverse|Default|Default-dark|Default-hc|Default-hc-dark) return 0 ;;
            esac
            for dir in "${gtk_dirs[@]}"; do
                if [ -d "$dir/$2/gtk-3.0" ] || [ -d "$dir/$2/gtk-4.0" ]; then return 0; fi
            done
            ;;
        icon | cursor)
            dirs=("$home/.icons")
            for dir in "${roots[@]}"; do dirs+=("$dir/icons"); done
            if [ "$1" = cursor ]; then
                _thm_cursor 0 "$2" "${dirs[@]}" && return 0
            else
                for dir in "${dirs[@]}"; do
                    if [ -f "$dir/$2/index.theme" ] && grep -q '^Directories=' "$dir/$2/index.theme"; then return 0; fi
                done
            fi
            ;;
        kvantum)
            # <dir>/<name>/<name>.kvconfig, <dir>/<base>/<name>.kvconfig for a
            # FooDark variant, or <gtk theme dir>/<name>/Kvantum/<name>.kvconfig.
            base="${2%Dark}"
            dirs=("$config_home/Kvantum")
            for dir in "${roots[@]}"; do dirs+=("$dir/Kvantum"); done
            for dir in "${dirs[@]}"; do
                [ -f "$dir/$2/$2.kvconfig" ] && return 0
                [ -n "$base" ] && [ -f "$dir/$base/$2.kvconfig" ] && return 0
            done
            for dir in "${gtk_dirs[@]}"; do
                [ -f "$dir/$2/Kvantum/$2.kvconfig" ] && return 0
            done
            ;;
    esac
    return 1
}

# _thm_gsettings <key> -> the org.gnome.desktop.interface value, unquoted, or
# nothing (no gsettings, no schema, no answer within 5 seconds: the timeout
# keeps a D-Bus activation hang from blocking the doctor).
_thm_gsettings() {
    local value
    value="$(timeout 5 gsettings get org.gnome.desktop.interface "$1" 2> /dev/null < /dev/null)" || return 0
    value="${value#\'}"
    printf '%s' "${value%\'}"
}

# _thm_ini <file> <section> <key> -> the key's value in that section, or nothing.
_thm_ini() {
    awk -v want="$2" -v key="$3" '
        /^[[:space:]]*\[/ { s = $0; gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "", s); in_s = (s == want); next }
        in_s {
            line = $0; sub(/^[[:space:]]+/, "", line)
            k = line; sub(/[[:space:]]*=.*$/, "", k)
            if (k == key && line ~ /=/) {
                sub(/^[^=]*=[[:space:]]*/, "", line); sub(/[[:space:]\r]+$/, "", line); print line; exit
            }
        }
    ' "$1"
}

# _thm_first_line <file> -> the first line, trimmed, or nothing.
_thm_first_line() {
    local value=""
    IFS= read -r value < "$1" || true
    value="${value%$'\r'}"
    value="${value#"${value%%[![:space:]]*}"}"
    printf '%s' "${value%"${value##*[![:space:]]}"}"
}

# _thm_add <kind> <name> <source> -- records a selected theme that is not
# installed, one entry per kind and name however many files select it. Fills
# the caller's keys and sources.
_thm_add() {
    [ -n "$2" ] || return 0
    _thm_present "$1" "$2" && return 0
    local key="$1|$2"
    if [ -z "${sources[$key]+x}" ]; then
        keys+=("$key")
        sources[$key]="$3"
    else
        sources[$key]+=", $3"
    fi
}

check_themes() {
    group "Themes"
    local file live name src kind key before=$((DOCTOR_WARNINGS + DOCTOR_NOTICES))
    local -a keys=()
    local -A sources=()

    local gkey
    for gkey in gtk-theme:gtk icon-theme:icon cursor-theme:cursor; do
        _thm_add "${gkey#*:}" "$(_thm_gsettings "${gkey%:*}")" "gsettings org.gnome.desktop.interface ${gkey%:*}"
    done

    while IFS= read -r -d '' file; do
        live="$DOCTOR_ROOT/${file#defaults/}"
        [ -f "$live" ] || live="$DOCTOR_ROOT/$file"
        src="${live#"$DOCTOR_ROOT"/}"
        case "$file" in
            defaults/gtk-[0-9].0/settings.ini)
                _thm_add gtk "$(_thm_ini "$live" Settings gtk-theme-name)" "$src"
                _thm_add icon "$(_thm_ini "$live" Settings gtk-icon-theme-name)" "$src"
                _thm_add cursor "$(_thm_ini "$live" Settings gtk-cursor-theme-name)" "$src"
                ;;
            defaults/qt[0-9]ct/qt[0-9]ct.conf)
                _thm_add icon "$(_thm_ini "$live" Appearance icon_theme)" "$src"
                ;;
            defaults/options/cursortheme)
                # Empty is not "no preference": apptype.lua falls back to the default.
                name="$(_thm_first_line "$live")"
                [ -n "$name" ] || { name="$(_thm_first_line "$DOCTOR_ROOT/$file")"; src="$file"; }
                _thm_add cursor "$name" "$src"
                ;;
        esac
    done < <(git -C "$DOCTOR_ROOT" ls-files -z -- 'defaults/' 2>/dev/null)

    live="$DOCTOR_ROOT/Kvantum/kvantum.kvconfig"
    if [ -f "$live" ]; then
        name="$(_thm_ini "$live" General theme)"
        case "${name,,}" in
            default) ;;
            *) _thm_add kvantum "$name" "Kvantum/kvantum.kvconfig" ;;
        esac
    fi

    for key in "${keys[@]}"; do
        kind="${key%%|*}"
        name="${key#*|}"
        case "$kind" in
            gtk)
                warn "No GTK theme '$name', selected by ${sources[$key]}, so GTK apps fall back to Adwaita" \
                    "sudo pacman -Fy, then pacman -F $(doctor_q "usr/share/themes/$name/gtk-3.0/gtk.css") names the repo package to install; an AUR theme is installed with the AUR helper, and install.sh lists the defaults in AUR_PACKAGES" ;;
            icon)
                warn "No icon theme '$name', selected by ${sources[$key]}, so icons fall back to hicolor" \
                    "sudo pacman -Fy, then pacman -F $(doctor_q "usr/share/icons/$name/index.theme") names the package to install" ;;
            cursor)
                warn "No cursor theme '$name', selected by ${sources[$key]}, so the cursor falls back to the default theme" \
                    "sudo pacman -Fy, then pacman -F $(doctor_q "usr/share/icons/$name/index.theme") names the repo package to install; an AUR theme is installed with the AUR helper, and install.sh lists the defaults in AUR_PACKAGES" ;;
            kvantum)
                warn "No Kvantum theme '$name', selected by ${sources[$key]}, so Kvantum apps fall back to its default look" \
                    "sudo pacman -Fy, then pacman -F $(doctor_q "usr/share/Kvantum/$name/$name.kvconfig") names the package to install" ;;
        esac
    done

    if [ $((DOCTOR_WARNINGS + DOCTOR_NOTICES)) -eq "$before" ]; then
        ok "Every selected GTK, icon, cursor and Kvantum theme is installed"
    fi
}
