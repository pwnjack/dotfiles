#!/bin/bash
# Render the settings panel's Bar page for Waybar's built-in resource modules
# into the include waybar/config.jsonc names. Only cpu, memory and disk are
# handled here: they are Waybar built-ins and can only be hidden through
# config. custom/gpu, custom/network and custom/updates read their own
# options/bar-* file, so a hidden script skips its own work.
#
# Each mode blanks per-state formats. config.jsonc gives these modules a
# "normal" state below "warning", and a module whose format renders empty is
# hidden:
#   always  nothing rendered
#   high    format-normal ""                  (shows from warning up)
#   hidden  format-normal/-warning/-critical ""
# config.jsonc must never set those three keys itself: the main file wins
# over an include key by key, so a mode would silently stop working.
#
# Layout options (bar-position, -style, -opacity, -border, -output) are
# rendered too: position, margins and output as top-level keys of the include,
# the look as the stylesheet waybar/bar.css links to (BAR_CSS). config.jsonc
# and style.css must not set those keys themselves, for the same reason: the
# main config wins over an include key by key, and a later style.css rule wins
# over an import.
#
# Always leaves the include in place ({} when every module is "always"), so a
# fresh checkout or a missing option still shows every module.
set -euo pipefail
options=$HOME/.config/options
include=$HOME/.local/state/waybar/bar.jsonc
options=${BAR_OPTIONS:-$options}
include=${BAR_INCLUDE:-$include}
css=$HOME/.local/state/waybar/bar.css
css=${BAR_CSS:-$css}

# opt <name> — first line of options/<name>, empty when missing
opt() {
    local v=''
    read -r v 2>/dev/null < "$options/$1" || true
    printf '%s' "$v"
}

position=$(opt bar-position)
[[ $position == bottom ]] || position=top
style=$(opt bar-style)
[[ $style == docked ]] || style=floating
border=$(opt bar-border)
[[ $border == disabled ]] || border=enabled
opacity=$(opt bar-opacity)
# Matched as text, never compared as a number first: bash arithmetic wraps a
# long enough digit string round to 0 or a negative, which would pass a <= 100
# test and render a transparent or invalid background.
if [[ $opacity =~ ^0*(100|[0-9]{1,2})$ ]]; then
    opacity=$((10#${BASH_REMATCH[1]}))
else
    opacity=80
fi
if ((opacity == 100)); then
    alpha=1
else
    printf -v alpha '0.%02d' "$opacity"
fi
output=$(opt bar-output)
[[ $output =~ ^[A-Za-z0-9._-]+$ ]] || output=''

if [[ $style == docked ]]; then
    margin_edge=0 margin_side=0 radius=0
    if [[ $position == top ]]; then edge=bottom; else edge=top; fi
    border_rule="border-$edge: 1px solid @foreground;"
else
    margin_edge=8 margin_side=10 radius=18
    border_rule='border: 1px solid @foreground;'
fi
[[ $border == enabled ]] || border_rule='border: none;'
if [[ $position == top ]]; then
    margin_top=$margin_edge margin_bottom=0
else
    margin_top=0 margin_bottom=$margin_edge
fi

entries=()
for module in cpu memory disk; do
    mode=''
    read -r mode 2>/dev/null < "$options/bar-$module" || true
    case $mode in
        high) entries+=("\"$module\": { \"format-normal\": \"\" }") ;;
        hidden) entries+=("\"$module\": { \"format-normal\": \"\", \"format-warning\": \"\", \"format-critical\": \"\" }") ;;
    esac
done

mkdir -p "${include%/*}"
tmp=$(mktemp "$include.XXXXXX")
trap 'rm -f "$tmp"' EXIT
{
    printf '{\n  "position": "%s",\n  "margin-top": %s,\n  "margin-bottom": %s,\n  "margin-left": %s,\n  "margin-right": %s' \
        "$position" "$margin_top" "$margin_bottom" "$margin_side" "$margin_side"
    [[ -z $output ]] || printf ',\n  "output": "%s"' "$output"
    sep=','
    for entry in "${entries[@]}"; do
        printf '%s\n  %s' "$sep" "$entry"
        sep=','
    done
    printf '\n}\n'
} > "$tmp"
mv -f "$tmp" "$include"

mkdir -p "${css%/*}"
tmp=$(mktemp "$css.XXXXXX")
{
    printf 'window#waybar {\n    background: alpha(@background, %s);\n' "$alpha"
    [[ $border_rule == 'border: none;' ]] || printf '    %s\n' "$border_rule"
    printf '    border-radius: %spx;\n}\n' "$radius"
} > "$tmp"
mv -f "$tmp" "$css"
# Reload through waybar.sh, never a bare USR2: Proton VPN's tray icon does not
# re-register after one, and waybar.sh restores it. Only a running bar is
# reloaded -- waybar.sh would start one, and a settings change must not bring
# back a bar the user toggled off.
if [[ ${1:-} != --no-reload ]] && pgrep -x waybar >/dev/null 2>&1; then
    bash "$(dirname -- "${BASH_SOURCE[0]}")/waybar.sh" || true
fi
