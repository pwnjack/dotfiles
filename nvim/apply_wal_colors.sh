#!/bin/bash
#
# Render the matugen palette and re-theme running Neovim instances.
#
# Render ~/.cache/wal/colors-wal.vim in the layout pywal16.nvim expects;
# nvim/lua/plugins/colorscheme.lua loads it at startup.
# Each instance listens on $XDG_RUNTIME_DIR/nvim.<pid>.0 by default; asking it
# to run `colorscheme pywal16` again re-reads the file. --remote-expr evaluates
# without typing into the instance, so a buffer in insert mode is untouched.
# An instance whose user switched to another scheme is left alone.
#
# A socket can outlive a crashed instance, and an instance can be busy, so
# each request is bounded and its failure ignored: a stale editor is not a
# theming failure.
#

set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_root="${XDG_CACHE_HOME:-$HOME/.cache}"
cache_dir="$cache_root/wal"

declare -a wal=()
# shellcheck source=scripts/theming/palette.sh
# shellcheck disable=SC1091
. "$config_dir/scripts/theming/palette.sh"
wal_load

wallpaper=""
if [ -e "$cache_root/current_wallpaper" ]; then
    wallpaper=$(readlink -f "$cache_root/current_wallpaper" 2>/dev/null) || wallpaper=""
fi
# Preserve paths containing backslashes or quotes in Vim's double-quoted string.
wallpaper=${wallpaper//\\/\\\\}
wallpaper=${wallpaper//\"/\\\"}

mkdir -p "$cache_dir" || exit 1
output_tmp="$cache_dir/colors-wal.vim.tmp.$$"
trap 'rm -f "$output_tmp"' EXIT
{
    printf '%s\n' '" Special'
    printf 'let wallpaper = "%s"\n' "$wallpaper"
    printf 'let background = "%s"\n' "${wal[0],,}"
    printf 'let foreground = "%s"\n' "${wal[7],,}"
    printf 'let cursor = "%s"\n\n' "${wal[7],,}"
    printf '%s\n' '" Colors'
    for ((i = 0; i < 16; i++)); do
        printf 'let color%d = "%s"\n' "$i" "${wal[$i],,}"
    done
} > "$output_tmp" || exit 1
mv "$output_tmp" "$cache_dir/colors-wal.vim" || exit 1
trap - EXIT

command -v nvim >/dev/null 2>&1 || exit 0
runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

shopt -s nullglob
for socket in "$runtime_dir"/nvim.*.0; do
    [ -S "$socket" ] || continue
    timeout 2 nvim --server "$socket" --remote-expr \
        'execute(get(g:, "colors_name", "") ==# "pywal16" ? "colorscheme pywal16" : "")' \
        >/dev/null 2>&1 || true
done

exit 0
