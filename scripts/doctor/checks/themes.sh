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
# Themes are looked up where the toolkits look: ~/.themes,
# ~/.local/share/themes and /usr/share/themes for GTK; ~/.icons,
# ~/.local/share/icons and /usr/share/icons for icons and cursors;
# ~/.config/Kvantum and /usr/share/Kvantum for Kvantum.
#
# Severity is WARN: the session starts and looks wrong, nothing breaks.
#
# Accepted risk: a GTK theme counts as installed when it has a gtk-3.0 or a
# gtk-4.0 directory, so one that ships only the other major version is not
# reported, and GTK's built-in themes are not looked up.

# _thm_present <kind> <name> -- host probe: the theme is installed. Kind is gtk,
# icon, cursor or kvantum. DOCTOR_THEME_HOME and DOCTOR_THEME_SHARE stand in for
# $HOME and /usr/share, so a test can aim the lookup at a fixture.
_thm_present() {
    local home="${DOCTOR_THEME_HOME:-$HOME}" share="${DOCTOR_THEME_SHARE:-/usr/share}" dir
    local -a dirs
    case "$2" in
        */*) return 1 ;;
    esac
    case "$1" in
        gtk)
            case "$2" in
                Adwaita|Adwaita-dark|HighContrast|HighContrastInverse|Default) return 0 ;;
            esac
            dirs=("$home/.themes" "$home/.local/share/themes" "$share/themes")
            for dir in "${dirs[@]}"; do
                if [ -d "$dir/$2/gtk-3.0" ] || [ -d "$dir/$2/gtk-4.0" ]; then return 0; fi
            done
            ;;
        icon | cursor)
            dirs=("$home/.icons" "$home/.local/share/icons" "$share/icons")
            for dir in "${dirs[@]}"; do
                if [ "$1" = cursor ]; then
                    [ -d "$dir/$2/cursors" ] && return 0
                else
                    [ -f "$dir/$2/index.theme" ] && return 0
                fi
            done
            ;;
        kvantum)
            dirs=("$home/.config/Kvantum" "$share/Kvantum")
            for dir in "${dirs[@]}"; do
                [ -f "$dir/$2/$2.kvconfig" ] && return 0
            done
            ;;
    esac
    return 1
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

    while IFS= read -r -d '' file; do
        case "$file" in
            defaults/gtk-[0-9].0/settings.ini)
                live="$DOCTOR_ROOT/${file#defaults/}"
                [ -f "$live" ] || live="$DOCTOR_ROOT/$file"
                src="${live#"$DOCTOR_ROOT"/}"
                _thm_add gtk "$(_thm_ini "$live" Settings gtk-theme-name)" "$src"
                _thm_add icon "$(_thm_ini "$live" Settings gtk-icon-theme-name)" "$src"
                _thm_add cursor "$(_thm_ini "$live" Settings gtk-cursor-theme-name)" "$src"
                ;;
            defaults/qt[0-9]ct/qt[0-9]ct.conf)
                live="$DOCTOR_ROOT/${file#defaults/}"
                [ -f "$live" ] || live="$DOCTOR_ROOT/$file"
                _thm_add icon "$(_thm_ini "$live" Appearance icon_theme)" "${live#"$DOCTOR_ROOT"/}"
                ;;
            defaults/options/cursortheme)
                live="$DOCTOR_ROOT/${file#defaults/}"
                [ -f "$live" ] || live="$DOCTOR_ROOT/$file"
                _thm_add cursor "$(_thm_first_line "$live")" "${live#"$DOCTOR_ROOT"/}"
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
                warn "No GTK theme '$name', which ${sources[$key]} select, so GTK apps fall back to Adwaita" \
                    "sudo pacman -Fy, then pacman -F $(doctor_q "usr/share/themes/$name/gtk-3.0/gtk.css") names the package to install" ;;
            icon)
                warn "No icon theme '$name', which ${sources[$key]} select, so icons fall back to hicolor" \
                    "sudo pacman -Fy, then pacman -F $(doctor_q "usr/share/icons/$name/index.theme") names the package to install" ;;
            cursor)
                warn "No cursor theme '$name', which ${sources[$key]} select, so the cursor falls back to the default theme" \
                    "sudo pacman -Fy, then pacman -F $(doctor_q "usr/share/icons/$name/index.theme") names the package to install" ;;
            kvantum)
                warn "No Kvantum theme '$name', which ${sources[$key]} selects, so Kvantum apps fall back to its default look" \
                    "sudo pacman -Fy, then pacman -F $(doctor_q "usr/share/Kvantum/$name/$name.kvconfig") names the package to install" ;;
        esac
    done

    if [ $((DOCTOR_WARNINGS + DOCTOR_NOTICES)) -eq "$before" ]; then
        ok "Every selected GTK, icon, cursor and Kvantum theme is installed"
    fi
}
