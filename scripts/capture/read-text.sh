#!/bin/bash
#
# Copy a QR code, a barcode or text from a screenshot to the clipboard.
#
# Usage: <PNG on stdin> | read-text.sh
#
# The last stage of `screenshot.sh region --text`, which pipes hyprshot's raw
# capture here. Decoding goes in this order:
#
#   1. zbarimg: any QR code or barcode wins, and its payload is copied (one
#      line per symbol when there are several);
#   2. tesseract, English and Italian: the recognised text is copied.
#
# Empty input (a cancelled selection) exits quietly. Every outcome but that one
# ends in a toast, so a miss is never silent, and a copy is announced only once
# wl-copy has succeeded. The recognised text goes to
# wl-copy on stdin and to notify-send as its body, nowhere else; the one
# exception is the Open action on a lone URL, which hands xdg-open that URL.
#
# The language retry costs a second tesseract run only when the first failed,
# which is what a missing Italian data file does.

# shellcheck source=scripts/capture/toast.sh
. "${BASH_SOURCE[0]%/*}/toast.sh"

# Bash 5.2 would read a & in a replacement as "the match"; preview() wants the character.
shopt -u patsub_replacement 2>/dev/null

have() { command -v "$1" >/dev/null 2>&1; }

# Markup-safe body: first line, cut to 80 characters.
preview() {
    local line=${1%%$'\n'*}
    (( ${#line} > 80 )) && line="${line:0:79}…"
    line=${line//&/&amp;}
    line=${line//</&lt;}
    printf '%s' "${line//>/&gt;}"
}

# toast <icon> <title> [body]; `--` keeps a body that starts with "-" a body.
toast() {
    have notify-send || return 0
    notify-send -a Capture -i "$1" -- "$2" "${3-}"
}

dir=${XDG_RUNTIME_DIR:-}
[ -d "$dir" ] && [ -w "$dir" ] || dir=
file=$(mktemp --suffix=.png --tmpdir"${dir:+=$dir}" read-text.XXXXXX) || exit 1
trap 'rm -f "$file"' EXIT
cat > "$file"
[ -s "$file" ] || exit 0

# copy <text> -- the clipboard, or a toast saying it failed (wl-copy missing,
# or unable to reach the compositor). Succeeds only when the text was copied.
copy() {
    have wl-copy && printf '%s' "$1" | wl-copy && return 0
    toast dialog-warning 'Could not copy to the clipboard'
    return 1
}

# --- QR codes and barcodes -------------------------------------------------
# --raw prints each payload as it is, with no TYPE: prefix to parse, so a
# payload line that happens to read "QR-Code:..." stays content. Exit 4 means
# there was no symbol.
text=
have zbarimg && text=$(zbarimg -q --raw "$file" 2>/dev/null)
if [ -n "$text" ]; then
    copy "$text" || exit 0
    if [[ $text =~ ^https?://[^[:space:]]+$ ]] && have notify-send; then
        open_toast edit-copy 'Code copied' "$(preview "$text")" "$text"
    else
        toast edit-copy 'Code copied' "$(preview "$text")"
    fi
    exit 0
fi

# --- Text ------------------------------------------------------------------
if ! have tesseract; then
    toast dialog-warning 'Text recognition needs tesseract'
    exit 0
fi
text=$(tesseract "$file" - -l eng+ita 2>/dev/null) || text=$(tesseract "$file" - -l eng 2>/dev/null)
text=${text%"${text##*[![:space:]]}"}      # trailing whitespace and form feeds
if [ -z "$text" ]; then
    toast dialog-information 'No text found'
    exit 0
fi
copy "$text" || exit 0
toast edit-copy 'Text copied' "$(preview "$text")"
