#!/bin/bash
#
# Sourced by record.sh, screenshot.sh and read-text.sh: the toasts they post
# that outlive the script.
#
# saved_toast <icon> <title> <body> <file> -- a detached toast with Open and
# Show in folder, so the caller returns at once. notify-send --wait blocks
# until the toast is gone and prints the chosen action. Callers holding locks
# close those descriptors on the call, or the toast would keep them held.
#
# Show in folder asks org.freedesktop.FileManager1, which
# scripts/settings/file-manager.sh points at the configured file manager, to
# select the file; without that service it opens the folder instead.
saved_toast() {
    local icon=$1 title=$2 body=$3 file=$4
    (
        exec </dev/null >/dev/null 2>&1
        choice=$(notify-send -a Capture -i "$icon" --wait \
            -A open=Open -A folder='Show in folder' "$title" "$body") || exit 0
        case $choice in
            open) exec xdg-open "$file" ;;
            folder)
                gdbus call --session --dest org.freedesktop.FileManager1 \
                    --object-path /org/freedesktop/FileManager1 \
                    --method org.freedesktop.FileManager1.ShowItems "['file://$file']" '' \
                    || exec xdg-open "${file%/*}" ;;
        esac
    ) &
}

# open_toast <icon> <title> <body> <url> -- a detached toast with one Open
# action, for a copied link. Returns at once, like saved_toast.
open_toast() {
    local icon=$1 title=$2 body=$3 url=$4
    (
        exec </dev/null >/dev/null 2>&1
        choice=$(notify-send -a Capture -i "$icon" --wait -A open=Open -- "$title" "$body") || exit 0
        [ "$choice" = open ] && exec xdg-open "$url"
    ) &
}
