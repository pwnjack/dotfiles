#!/bin/bash
#
# Run a terminal program whose ANSI green follows the wallpaper accent.
#
# cmatrix and tty-clock draw in ANSI green, and slot 2 stays a readable green
# on every palette (docs/internals/theming.md), so on their own they barely
# change with the wallpaper. For the wrapped program only, this overrides
# slots 2 and 10 with `primary` on its own terminal and resets those two slots
# when it exits; every other terminal keeps semantic green.
#
# Each wrapped terminal is registered as $XDG_RUNTIME_DIR/dotfiles/accent-ptys/
# <pid>, holding the pty path. On a palette change ghostty/apply_wal_colors.sh
# clears every pty's overrides, then runs `--refresh`, which re-applies the
# new accent to each registered pty that its process still has as stdin and
# drops every other registration.
#
# Usage: accent-run.sh <command> [args...]
#        accent-run.sh --refresh
#

set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
registry="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/dotfiles/accent-ptys"

# Prints the OSC 4 overrides for slots 2 and 10.
accent_sequence() {
    # shellcheck disable=SC2034  # read by role_load and wal_role
    declare -A role=()
    # shellcheck source=scripts/theming/palette.sh
    . "$config_dir/scripts/theming/palette.sh"
    role_load
    local accent
    accent=$(wal_role primary)
    printf '\033]4;2;%s\033\\\033]4;10;%s\033\\' "$accent" "$accent"
}

# A stuck pty must not stall a wallpaper change, so every write is bounded.
# Appending is the same as writing on a pty, and lets tests see the order of
# writes to a fake one.
write_pty() {
    timeout 1 sh -c 'printf "%s" "$2" >> "$1"' _ "$1" "$2" 2>/dev/null
}

refresh() {
    local entry pid pty sequence
    [ -d "$registry" ] || return 0
    sequence=$(accent_sequence)
    for entry in "$registry"/[0-9]*; do
        [ -f "$entry" ] || continue
        pid=${entry##*/}
        pty=
        IFS= read -r pty < "$entry"
        # A dead or reused pid no longer has this pty as stdin.
        if [ -z "$pty" ] || [ "$(readlink "/proc/$pid/fd/0" 2>/dev/null)" != "$pty" ]; then
            rm -f "$entry"
            continue
        fi
        [ -O "$pty" ] && [ -w "$pty" ] || continue
        write_pty "$pty" "$sequence" || true
    done
}

cleanup() {
    write_pty "$pty" $'\033]104;2;10\033\\'
    rm -f "$registry/$$"
}

if [ "${1:-}" = "--refresh" ]; then
    refresh
    exit 0
fi

if [ "$#" -eq 0 ]; then
    echo "Usage: accent-run.sh <command> [args...] | --refresh" >&2
    exit 2
fi
if ! command -v "$1" >/dev/null 2>&1; then
    echo "accent-run.sh: $1: command not found" >&2
    exit 127
fi

# Without a terminal there is nothing to colour.
pty=$(tty 2>/dev/null) || exec "$@"

trap cleanup EXIT
mkdir -p "$registry" 2>/dev/null && printf '%s\n' "$pty" > "$registry/$$"
write_pty "$pty" "$(accent_sequence)"
"$@"
exit
