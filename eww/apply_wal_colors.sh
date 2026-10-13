#!/bin/bash
#
# Render the pywal foreground as the desktop clock's SCSS colour partial.
#
# eww/eww.scss imports ~/.cache/wal/eww-colors.scss. The partial is written
# even before pywal has run (the shared loader supplies the fallback palette),
# so the stylesheet never imports a missing file. Nothing is done when eww is
# not installed; desktop-clock.sh renders the partial itself the first time it
# starts the clock.
#
# A running clock is recoloured through desktop-clock.sh, the one owner of
# `eww reload`, and only when the colour actually changed: a reload rebuilds
# the window. --no-reload renders and stops there (desktop-clock.sh uses it).
#

set -uo pipefail

command -v eww >/dev/null 2>&1 || exit 0

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
out="$cache_dir/eww-colors.scss"

declare -a wal=()
# shellcheck source=scripts/theming/palette.sh
. "$config_dir/scripts/theming/palette.sh"
wal_load

mkdir -p "$cache_dir"

# pywal's foreground is colour 7, which is what the Ghostty include uses too.
text="// Generated from the pywal palette by eww/apply_wal_colors.sh - do not edit
\$background: ${wal[0]};
\$foreground: ${wal[7]};"

# An unchanged palette needs no reload, unless the last one failed (the
# marker below), so a failed recolour is retried on the next palette run.
failed="$cache_dir/.eww-reload-failed"
if [ -r "$out" ] && [ "$(< "$out")" = "$text" ] && [ ! -e "$failed" ]; then
    exit 0
fi

tmp=$(mktemp "$out.XXXXXX") || exit 1
if ! { printf '%s\n' "$text" > "$tmp" && mv -f "$tmp" "$out"; }; then
    rm -f "$tmp"
    exit 1
fi

[ "${1:-}" = --no-reload ] && exit 0

# Detached from the caller's stderr (wall.sh reads it to the end) in case the
# reload ever leaves a process behind; a failure is kept and reported instead.
if err=$(bash "$config_dir/scripts/desktop-clock/desktop-clock.sh" reload </dev/null 2>&1 >/dev/null); then
    rm -f "$failed"
    exit 0
fi
touch "$failed"
printf '%s\n' "${err:-desktop-clock: reload failed}" >&2
exit 1
