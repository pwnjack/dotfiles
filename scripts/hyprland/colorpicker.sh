#!/bin/bash
#
# Colour picker -- pick a pixel, copy its hex, say so.
#
# This replaces a waybar `custom/hyprpicker` module that was deleted in
# d952dfa as defined-but-unreferenced. Do not restore that module's one-liner:
# it was wrong twice, and both mistakes are corrected here.
#
#   1. It used `color-select-symbolic`. swaync 0.12.6 reserves the icon slot
#      for Papirus-Dark symbolic icons and then draws nothing in it, so the
#      toast came up blank. The non-symbolic `color-select` is what renders.
#   2. It passed the colour as the notification TITLE with no body, which
#      styles the one piece of information as a heading.
#
# -b/--no-fancy suppresses hyprpicker's coloured output. Command substitution
# is not a TTY so it would likely stay clean anyway, but a stray escape
# sequence here goes silently into the clipboard, which is not a failure mode
# worth leaving to chance.
#

# All three are guarded, not just hyprpicker. An unguarded wl-copy is the one
# failure mode that actively misinforms: the pipe fails, nothing reaches the
# clipboard, and the toast still says "Colour copied".
command -v hyprpicker >/dev/null 2>&1 || exit 0
command -v wl-copy    >/dev/null 2>&1 || exit 0

# -l/--lowercase-hex: hyprpicker emits uppercase by default (the flag's
# existence is what establishes that), and #a1b2c3 is what the rest of this
# repo's colour handling reads and writes.
color=$(hyprpicker -f hex -l -b -q) || exit 0   # ESC cancels: ordinary, not an error
[ -n "$color" ] || exit 0

printf '%s' "$color" | wl-copy || exit 1

command -v notify-send >/dev/null 2>&1 || exit 0
notify-send -i color-select 'Colour copied' "$color"
