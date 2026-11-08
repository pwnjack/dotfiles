#!/bin/bash
#
# Clipboard History
# Pick an entry to copy it again, or clear the whole history.
#
# cliphist lines always start with a numeric id and a tab, so the clear entry
# can never collide with one.
#

# Nerd Font glyphs, escaped so no editor can silently drop them.
clear=$'\uf1f8'"  Clear history"
yes=$'\uf058'" Yes"
no=$'\uf52f'" No"

chosen=$({ cliphist list; printf '%s\n' "$clear"; } | rofi -dmenu -no-custom -p "Clipboard")
[ -n "$chosen" ] || exit 0

if [ "$chosen" = "$clear" ]; then
    answer=$(printf '%s\n' "$no" "$yes" | rofi -dmenu -no-custom -p "Clear clipboard history?")
    if [ "$answer" = "$yes" ] && ! cliphist wipe; then
        command -v notify-send >/dev/null 2>&1 && \
            notify-send "Clipboard history" "Failed to clear clipboard history"
    fi
    exit 0
fi

# Decoded to a file first: an entry that has gone from the history, or one that
# fails to decode, must not reach wl-copy and replace the clipboard with nothing.
tmp=$(mktemp) || exit 1
trap 'rm -f -- "$tmp"' EXIT
printf '%s\n' "$chosen" | cliphist decode > "$tmp" && [ -s "$tmp" ] || exit 1
wl-copy < "$tmp"
