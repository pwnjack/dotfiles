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
# config.jsonc must never set those three keys, nor the disk's tooltip-format,
# itself: the main file wins over an include key by key, so a mode would
# silently stop working.
#
# Layout options (bar-position, -style, -opacity, -border, -output) are
# rendered too: position, margins and output as top-level keys of the include,
# the look as the stylesheet waybar/bar.css links to (BAR_CSS). config.jsonc
# and style.css must not set those keys themselves, for the same reason: the
# main config wins over an include key by key, and a later style.css rule wins
# over an import.
#
# Always leaves the include in place, so a fresh checkout or a missing option
# still shows every module.
set -euo pipefail
options=${BAR_OPTIONS:-$HOME/.config/options}
include=${BAR_INCLUDE:-$HOME/.local/state/waybar/bar.jsonc}
css=${BAR_CSS:-$HOME/.local/state/waybar/bar.css}

# shellcheck source=scripts/lib/options.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/options.sh"

position=$(option "$options/bar-position")
[[ $position == bottom ]] || position=top
style=$(option "$options/bar-style")
[[ $style == docked ]] || style=floating
border=$(option "$options/bar-border")
[[ $border == disabled ]] || border=enabled
opacity=$(option "$options/bar-opacity")
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
output=$(option "$options/bar-output")
[[ $output =~ ^[A-Za-z0-9._-]+$ ]] || output=''

if [[ $style == docked ]]; then
    margin_edge=0 margin_side=0 radius=0
    if [[ $position == top ]]; then edge=bottom; else edge=top; fi
    border_rule="border-$edge: 1px solid @foreground;"
else
    margin_edge=8 margin_side=10 radius=18
    border_rule='border: 1px solid @foreground;'
fi
if [[ $position == top ]]; then
    margin_top=$margin_edge margin_bottom=0
else
    margin_top=0 margin_bottom=$margin_edge
fi

# Since Waybar 0.16 the disk module shows its box when either the label or the
# tooltip renders, so a blanked disk blanks its tooltip too, or an empty,
# hoverable pill stays behind. That makes the tooltip a per-mode key, so it is
# rendered here like the formats: in "high" the readout shows without one.
disk_tooltip='Disk {percentage_used}%\n\nUsed: {used} / {total}\nFree: {free}'
entries=()
for module in cpu memory disk; do
    case $(option "$options/bar-$module") in
        high) keys='"format-normal": ""' ;;
        hidden) keys='"format-normal": "", "format-warning": "", "format-critical": ""' ;;
        *) keys='' ;;
    esac
    if [[ $module == disk ]]; then
        if [[ $keys ]]; then tip=''; else tip=$disk_tooltip; fi
        keys+="${keys:+, }\"tooltip-format\": \"$tip\""
    fi
    [[ -z $keys ]] || entries+=("\"$module\": { $keys }")
done

mkdir -p "${include%/*}"
tmp=$(mktemp "$include.XXXXXX")
trap 'rm -f "$tmp"' EXIT
{
    printf '{\n  "position": "%s",\n  "margin-top": %s,\n  "margin-bottom": %s,\n  "margin-left": %s,\n  "margin-right": %s' \
        "$position" "$margin_top" "$margin_bottom" "$margin_side" "$margin_side"
    [[ -z $output ]] || printf ',\n  "output": "%s"' "$output"
    for entry in "${entries[@]}"; do
        printf ',\n  %s' "$entry"
    done
    printf '\n}\n'
} > "$tmp"
mv -f "$tmp" "$include"

mkdir -p "${css%/*}"
tmp=$(mktemp "$css.XXXXXX")
{
    printf 'window#waybar {\n    background: alpha(@background, %s);\n' "$alpha"
    [[ $border == enabled ]] && printf '    %s\n' "$border_rule"
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
