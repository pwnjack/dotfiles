#!/bin/bash
#
# Make the configured terminal (options/terminal) the one xdg-terminal-exec
# opens. That is how GLib apps (a file manager's "Open with", GTK launchers) and uwsm
# run a desktop entry with Terminal=true, such as nvim, yazi or btop; with no
# preference it picks whichever terminal it finds first.
#
# This writes ${XDG_CONFIG_HOME:-~/.config}/xdg-terminals.list naming the
# desktop entry that is a TerminalEmulator and whose Exec runs the configured
# binary; hidden helper entries and file openers are skipped, and entries are
# taken in C-locale order so the choice never depends on the locale. The list
# is per-machine state: the .gitignore whitelist leaves it untracked. A list
# without this script's first line was written by hand and is left alone; a
# terminal with no desktop entry removes this script's list, which leaves
# xdg-terminal-exec's own choice.
#
# Run by install.sh and by the settings panel when the Terminal row changes.
# Idempotent; always exits 0, because a stale list only costs Terminal=true
# entries their terminal.

set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
target="$config_dir/xdg-terminals.list"
marker="# Written by scripts/settings/terminal.sh from options/terminal; edits are replaced."

term=""
{ read -r term < "$config_dir/options/terminal"; } 2>/dev/null
read -r term _ <<< "$term"   # the binary is the first word; the option may carry arguments
term="${term:-ghostty}"

# key <file> <key> -> the first value of <key> in [Desktop Entry]
key() {
    awk -v key="$2" '
        /^[[:space:]]*\[/ { main = ($0 ~ /^[[:space:]]*\[Desktop Entry\][[:space:]]*$/); next }
        main && $0 ~ "^" key "[[:space:]]*=" { sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]\r]+$/, ""); print; exit }
    ' "$1"
}

# exec_word <file> -> the first word of Exec, either quote style honoured
exec_word() {
    local value
    value="$(key "$1" Exec)"
    case "$value" in
        \"*) value="${value#\"}"; printf '%s\n' "${value%%\"*}" ;;
        \'*) value="${value#\'}"; printf '%s\n' "${value%%\'*}" ;;
        *) printf '%s\n' "${value%%[[:space:]]*}" ;;
    esac
}

entry=""
if binary=$(command -v -- "$term" 2>/dev/null) && [ -n "$binary" ]; then
    binary=$(readlink -f -- "$binary")
    IFS=: read -ra data_dirs <<< "${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    declare -A seen=()
    for dir in "${data_dirs[@]}"; do
        apps="$dir/applications"
        [ -d "$apps" ] || continue
        while IFS= read -r -d '' file; do
            # The desktop entry ID is the path under applications/ with / as -,
            # and the first directory that has an ID shadows the later ones.
            id="${file#"$apps"/}"
            id="${id//\//-}"
            [ -z "${seen[$id]:-}" ] || continue
            seen[$id]=1
            case ";$(key "$file" Categories);" in *";TerminalEmulator;"*) ;; *) continue ;; esac
            case "$(key "$file" Hidden)" in true) continue ;; esac
            # A hidden helper entry is not the terminal: kitty-open.desktop
            # runs "kitty +open %U", which would read the command as URLs.
            case "$(key "$file" NoDisplay)" in true) continue ;; esac
            case "$(key "$file" Exec)" in *%[fFuU]*) continue ;; esac
            word="$(exec_word "$file")"
            [ -n "$word" ] || continue
            resolved=$(command -v -- "$word" 2>/dev/null) || continue
            [ "$(readlink -f -- "$resolved")" = "$binary" ] || continue
            entry="$id"
            break 2
        done < <(find -L "$apps" -name '*.desktop' -type f -print0 2>/dev/null | LC_ALL=C sort -z)
    done
fi

owned=0
if [ ! -e "$target" ] || [ "$(head -n 1 -- "$target" 2>/dev/null)" = "$marker" ]; then owned=1; fi

if [ "$owned" = 1 ]; then
    if [ -n "$entry" ]; then
        content="$(printf '%s\n%s' "$marker" "$entry")"
        if [ "$(cat -- "$target" 2>/dev/null)" != "$content" ]; then
            mkdir -p -- "$config_dir" && printf '%s\n' "$content" > "$target"
        fi
    else
        rm -f -- "$target"
    fi
fi

exit 0
