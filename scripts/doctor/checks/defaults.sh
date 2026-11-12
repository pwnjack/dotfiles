#!/bin/bash
#
# Default applications: the programs other software opens on your behalf.
# Three mechanisms, each derived from the tracked file that declares it:
#
#   1. Environment. Every hl.env("NAME", apps.KEY ...) line in envvars.lua
#      exports an options/ value (apptype.lua maps KEY to its option and
#      fallback). The variable as this shell and the systemd user manager see
#      it must name an installed program: a stale export (BROWSER=firefox from
#      a distro ~/.profile, with Firefox gone) made gh fail to open a page. A
#      value that differs from the option is only stale (INFO).
#   2. xdg-terminal-exec, which GLib apps and uwsm use for Terminal=true
#      entries, must run and open options/terminal. A hand-written stub
#      earlier in PATH ran "$TERMINAL -e" with TERMINAL unset.
#   3. mimeapps.list. An association whose desktop entry exists but whose
#      program is gone (an uninstalled app's leftover entry) is launched and
#      fails. Entries for apps this machine never had are skipped: lookups fall
#      back past them, and the file is shared between machines.
#
# Whether the options themselves name installed programs is check_binaries'
# job, through the keybinds that launch them.

# Desktop entry directories in lookup order (the user's first), and the config
# directory xdg-terminal-exec reads its lists from.
DOCTOR_APPS_DIRS="${DOCTOR_APPS_DIRS:-${XDG_DATA_HOME:-$HOME/.local/share}/applications:$(printf '%s' "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" | sed 's#\(:\|$\)#/applications\1#g')}"
DOCTOR_XTE_CONFIG="${DOCTOR_XTE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}}"

# Host probes, each its own function so tests can stub them.
_def_have() { type -P -- "$1" >/dev/null 2>&1; }
_def_path() { type -P -- "$1" 2>/dev/null; }
_def_resolve() { local p; p="$(_def_path "$1")" && readlink -f -- "$p"; }
_def_env() { printenv "$1"; }
_def_systemd_raw() {
    command -v systemctl >/dev/null 2>&1 || return 0
    timeout 5 systemctl --user show-environment 2>/dev/null
}
# systemd prints a value with spaces or quotes as $'...'; undo that quoting.
_def_systemd_env() {
    local value
    value="$(_def_systemd_raw | sed -n "s/^$1=//p")"
    case "$value" in
        \$\'*\') value="${value#\$\'}"; value="${value%\'}"; value="${value//\\\'/\'}"; printf '%b\n' "$value" ;;
        *) printf '%s\n' "$value" ;;
    esac
}
# Bounded, and with a throwaway cache: a stub could open a window or hang, and
# the real one caches its choice in XDG_CACHE_HOME, which the doctor must not
# write.
_def_xte_path() {
    local cache
    cache="$(mktemp -d)" || return 0
    XDG_CACHE_HOME="$cache" timeout 5 xdg-terminal-exec --print-path 2>/dev/null < /dev/null
    rm -rf -- "$cache"
}
_def_desktops() { printf '%s' "${XDG_CURRENT_DESKTOP:-}" | tr '[:upper:]:' '[:lower:] '; }

# _def_word <command line> -> its first word, either quote style honoured
_def_word() {
    case "$1" in
        \"*) local v="${1#\"}"; printf '%s\n' "${v%%\"*}" ;;
        \'*) local v="${1#\'}"; printf '%s\n' "${v%%\'*}" ;;
        *) local v="${1#"${1%%[![:space:]]*}"}"; printf '%s\n' "${v%%[[:space:]]*}" ;;
    esac
}

# _def_value_word <name> <value> -> the program a variable's value runs: past
# leading VAR=x assignments, and the first of $BROWSER's colon-separated list.
_def_value_word() {
    local value="$2" assignment='^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=("[^"]*"|'"'[^']*'"'|[^[:space:]]*)([[:space:]]+(.*))?$'
    [ "$1" = BROWSER ] && value="${value%%:*}"
    while [[ "$value" =~ $assignment ]]; do value="${BASH_REMATCH[3]}"; done
    _def_word "$value"
}

# _def_option <key> -> the options/ value apptype.lua gives apps.<key>
_def_option() {
    local line name fallback value=""
    line="$(grep -E "^[[:space:]]*$1[[:space:]]*=[[:space:]]*read_option\(" "$DOCTOR_ROOT/hypr/config/apptype.lua" 2>/dev/null | head -n 1)"
    [ -n "$line" ] || return 1
    name="$(printf '%s' "$line" | sed -E 's/.*read_option\("([^"]*)".*/\1/')"
    fallback="$(printf '%s' "$line" | sed -nE 's/.*read_option\("[^"]*",[[:space:]]*"([^"]*)"\).*/\1/p')"
    { read -r value < "$DOCTOR_ROOT/options/$name"; } 2>/dev/null
    printf '%s\n' "${value:-$fallback}"
}

# _def_entry <desktop id> -> the path of the entry that answers to it. An ID's
# dashes may stand for subdirectories (kde-org.kde.foo.desktop is
# kde/org.kde.foo.desktop), so those are matched by their whole relative path.
_def_entry() {
    local dir file rel
    while IFS= read -r -d: dir; do
        [ -n "$dir" ] && [ -d "$dir" ] || continue
        if [ -f "$dir/$1" ]; then printf '%s\n' "$dir/$1"; return 0; fi
        case "$1" in *-*) ;; *) continue ;; esac
        while IFS= read -r -d '' file; do
            rel="${file#"$dir"/}"
            if [ "${rel//\//-}" = "$1" ]; then printf '%s\n' "$file"; return 0; fi
        done < <(find -L "$dir" -mindepth 2 -name '*.desktop' -type f -print0 2>/dev/null | LC_ALL=C sort -z)
    done <<< "$DOCTOR_APPS_DIRS:"
    return 1
}

# _def_entry_missing <file> -> what the entry runs that is not installed
_def_entry_missing() {
    local tryexec word missing=""
    tryexec="$(doctor_ini "$1" 'Desktop Entry' TryExec)"
    word="$(_def_word "$(doctor_ini "$1" 'Desktop Entry' Exec)")"
    if [ -n "$tryexec" ] && ! _def_have "$tryexec"; then missing="$tryexec"; fi
    if [ -n "$word" ] && [ "$word" != "$tryexec" ] && ! _def_have "$word"; then
        missing="${missing:+$missing and }$word"
    fi
    printf '%s' "$missing"
}

_def_check_env() {
    local envvars="$DOCTOR_ROOT/hypr/config/setup/envvars.lua" name key want where value word
    [ -f "$envvars" ] || return 0
    while read -r name key; do
        want="$(_def_option "$key")" || continue
        for where in shell systemd; do
            if [ "$where" = shell ]; then value="$(_def_env "$name")"; else value="$(_def_systemd_env "$name")"; fi
            [ -n "$value" ] || continue
            word="$(_def_value_word "$name" "$value")"
            [ -n "$word" ] || continue
            if ! _def_have "$word"; then
                # The options/ value itself: check_binaries reports that one.
                [ "$value" = "$want" ] && continue
                if [ "$where" = shell ]; then
                    warn "$name is $value in this shell, and $word is not installed" "open a new terminal; if it persists, remove the export (from ~/.profile, your shell's config or /etc/profile.d) and log in again"
                else
                    warn "$name is $value for systemd and D-Bus apps, and $word is not installed" "remove the export (from ~/.profile or /etc/profile.d), then log in again"
                fi
            elif [ "$value" != "$want" ] && [ "$where" = shell ]; then
                note "$name is $value in this shell, but options/ says $want" "hyprctl reload, then open a new terminal; if it persists, your shell's config sets it"
            fi
        done
    done < <(sed -nE 's/^[[:space:]]*hl\.env\("([A-Za-z_][A-Za-z0-9_]*)",[[:space:]]*apps\.([A-Za-z_]+).*/\1 \2/p' "$envvars")
}

_def_check_terminal() {
    _def_have xdg-terminal-exec || return 0
    local path entry word term
    path="$(_def_path xdg-terminal-exec)"
    entry="$(_def_xte_path)"
    if [ -z "$entry" ] || [ ! -f "$entry" ]; then
        warn "xdg-terminal-exec at $path does not work, so apps cannot open nvim, yazi or btop in a terminal" \
            "pacman -Qo $(doctor_q "$path") || rm $(doctor_q "$path"); if a package owns it, XTE_DEBUG=1 xdg-terminal-exec --print-path says why"
        return 0
    fi
    term="$(_def_word "$(_def_option terminal)")"
    word="$(_def_word "$(doctor_ini "$entry" 'Desktop Entry' Exec)")"
    [ -n "$term" ] && [ -n "$word" ] || return 0
    [ "$(_def_resolve "$word")" != "$(_def_resolve "$term")" ] || return 0
    # terminal.sh writes the generic list, but a desktop-specific one is read
    # first, and a hand-written generic one is never replaced.
    local desktop list hint marker
    marker="$(sed -n 's/^marker="\(.*\)"$/\1/p' "$DOCTOR_ROOT/scripts/settings/terminal.sh" 2>/dev/null)"
    hint="bash $(doctor_q "$DOCTOR_ROOT/scripts/settings/terminal.sh") (it needs a desktop entry for $term)"
    for desktop in $(_def_desktops); do
        list="$DOCTOR_XTE_CONFIG/$desktop-xdg-terminals.list"
        if [ -f "$list" ]; then hint="edit or remove $(doctor_q "$list"), which takes precedence"; break; fi
    done
    list="$DOCTOR_XTE_CONFIG/xdg-terminals.list"
    if [ "${hint#bash }" != "$hint" ] && [ -f "$list" ] && [ "$(head -n 1 -- "$list")" != "$marker" ]; then
        hint="edit $(doctor_q "$list"), written by hand, or remove it and run $hint"
    fi
    warn "xdg-terminal-exec opens ${entry##*/}, not options/terminal ($term)" "$hint"
}

_def_check_mime() {
    local list="$DOCTOR_ROOT/mimeapps.list" id file missing hint
    [ -f "$list" ] || return 0
    while IFS= read -r id; do
        file="$(_def_entry "$id")" || continue
        # Hidden=true means deleted: lookups skip the entry, nothing launches it.
        [ "$(doctor_ini "$file" 'Desktop Entry' Hidden)" = true ] && continue
        missing="$(_def_entry_missing "$file")"
        [ -n "$missing" ] || continue
        hint="pick another app on the settings panel's Default Apps page"
        # Only a per-user entry is the user's to delete; a packaged one is pacman's.
        case "$file" in "${DOCTOR_APPS_DIRS%%:*}"/*) hint="$hint, or rm $(doctor_q "$file") if the app is gone" ;; esac
        warn "mimeapps.list opens files or links with $id, which runs $missing, not installed" "$hint"
    done < <(awk '
        /^[[:space:]]*\[/ { on = ($0 ~ /^\[(Default Applications|Added Associations)\]/); next }
        on && /=/ { sub(/^[^=]*=/, ""); n = split($0, ids, ";"); for (i = 1; i <= n; i++) if (ids[i] != "") print ids[i] }
    ' "$list" | sort -u)
}

check_defaults() {
    group "Default applications"
    local before
    before=$(doctor_findings)
    _def_check_env
    _def_check_terminal
    _def_check_mime
    ok_if_clean "$before" "Every default application resolves to an installed program"
}
