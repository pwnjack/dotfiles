#!/bin/bash
#
# Capture a screenshot.
#
# Usage: screenshot.sh screen|window|region [--annotate|--text] [--delay N]
#
# The one capture command: Super+S, Super+Alt+S, Super+Shift+T and the capture
# strip all call it, so all of them honour options/capture-freeze ("true"
# freezes the screen while selecting).
#
#   screen     the focused monitor, no selection
#   window     click a window (hyprshot's own picker)
#   region     drag a rectangle
#   --annotate open the shot in swappy instead of writing it; where it lands
#              is then swappy's decision, from swappy/config
#   --text     read a QR code, a barcode or text in the shot and copy it
#              (scripts/capture/read-text.sh); no file is written
#   --delay N  wait N seconds first (the strip's delay; Super+S has none)
#
# Without --annotate or --text the file goes to ~/Pictures/Screenshots.
#
# --annotate and --text use hyprshot's LONG --raw, and never -s. Both rules
# come from reading /usr/bin/hyprshot rather than its --help:
#
#   * -s is a no-op here. save_geometry() does
#     `if [ $RAW -eq 1 ]; then grim -g "$geometry" -; return 0; fi`, returning
#     before send_notification(). In raw mode there is no notification to silence.
#   * `-r -s` only works by accident. hyprshot's short spec is `hf:o:m:dszr:t:`
#     -- `r:` declares a REQUIRED argument, though the long `raw` declares
#     none. getopt binds -s as -r's argument and it survives only because
#     hyprshot's -r arm shifts by one and re-parses. Reverse the two flags and
#     getopt fails; hyprshot never checks getopt's exit status, so it would
#     carry on with RAW=0, WRITE A FILE, and pipe nothing to swappy. `--raw`
#     takes no argument and cannot be reordered into that trap.
#

usage() {
    echo "usage: ${0##*/} screen|window|region [--annotate|--text] [--delay N]" >&2
    exit 2
}

mode="${1:-region}"
[ $# -gt 0 ] && shift
annotate=0 text=0 delay=0
while [ $# -gt 0 ]; do
    case "$1" in
        --annotate) annotate=1 ;;
        --text) text=1 ;;
        --delay) delay="${2-}"; shift ;;
        *) usage ;;
    esac
    shift
done
case "$mode" in
    screen|window|region) ;;
    *) usage ;;
esac
(( annotate && text )) && usage
[[ "$delay" =~ ^[0-9]+$ ]] || usage
delay=$((10#$delay))

command -v hyprshot >/dev/null 2>&1 || exit 0
(( annotate )) && ! command -v swappy >/dev/null 2>&1 && exit 0

if [ "$mode" = screen ]; then
    monitor=$(hyprctl monitors -j 2>/dev/null | jq -r 'first(.[] | select(.focused) | .name) // empty' 2>/dev/null)
    [ -n "$monitor" ] || exit 1
    args=(-m output -m "$monitor")
else
    args=(-m "$mode")
fi
[ "$mode" != screen ] && grep -qx true "$HOME/.config/options/capture-freeze" 2>/dev/null && args+=(-z)

(( delay > 0 )) && sleep "$delay"

if (( annotate )); then
    hyprshot "${args[@]}" --raw | swappy -f -
    exit
fi
if (( text )); then
    hyprshot "${args[@]}" --raw | "${BASH_SOURCE[0]%/*}/../capture/read-text.sh"
    exit
fi

# hyprshot saves and copies to the clipboard; -s drops its own toast, which has
# no actions, for the shared one with Open and Show in folder. A cancelled
# selection writes no file and gets no toast.
file="$HOME/Pictures/Screenshots/Screenshot_$(date '+%Y-%m-%d_%H:%M:%S').png"
hyprshot "${args[@]}" -s -o "${file%/*}" -f "${file##*/}"
[ -s "$file" ] || exit 0
# shellcheck source=scripts/capture/toast.sh
. "${BASH_SOURCE[0]%/*}/../capture/toast.sh"
saved_toast "$file" 'Screenshot saved' "${file##*/}, also copied to the clipboard" "$file"
