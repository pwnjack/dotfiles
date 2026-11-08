#!/bin/bash
# Route Spotify through scripts/spotify/launch.sh, which keeps SpotX (and
# Spicetify, when set up) applied across spotify-launcher's client updates.
#
#   scripts/spotify/setup.sh [--dry-run]
#
# It writes a per-user copy of spotify-launcher's desktop entry under the same
# id, with Exec pointed at the wrapper. The same id is what makes it win over
# the system copy everywhere: Rofi, and the x-scheme-handler/spotify default,
# which names spotify-launcher.desktop. Skipped when spotify-launcher is not
# installed. Idempotent and never interactive.
#
# Test seams: SPOTIFY_SETUP_REPO (the repo root), SPOTIFY_DESKTOP_SRC (the
# system entry), XDG_DATA_HOME; spotify-launcher and zip are looked up on PATH.
set -euo pipefail

repo="${SPOTIFY_SETUP_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
src="${SPOTIFY_DESKTOP_SRC:-/usr/share/applications/spotify-launcher.desktop}"
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
dest="$apps/spotify-launcher.desktop"
dry=false
case ${1:-} in
    "") ;;
    --dry-run) dry=true ;;
    *) echo "spotify: unknown option '$1'" >&2; exit 2 ;;
esac

if ! command -v spotify-launcher >/dev/null 2>&1; then
    echo "spotify: spotify-launcher is not installed; skipping"
    exit 0
fi
if [ ! -f "$src" ]; then
    echo "spotify: no $src to base the entry on; skipping" >&2
    exit 1
fi
command -v zip >/dev/null 2>&1 \
    || echo "spotify: SpotX needs zip, which is missing: sudo pacman -S zip" >&2

launch="$repo/scripts/spotify/launch.sh"
# Exec quoting has two escape layers and % starts a field code; a path that
# would need escaping is refused instead.
case $launch in
    *[\\\"\`\$%]*) echo "spotify: cannot quote $launch in a desktop entry" >&2; exit 1 ;;
esac
# Only the main group's Exec: a [Desktop Action] keeps its own.
entry=""
group=""
while IFS= read -r line || [ -n "$line" ]; do
    case $line in
        "["*"]") group=$line ;;
        Exec=*) [ "$group" = "[Desktop Entry]" ] && line="Exec=\"$launch\" %U" ;;
    esac
    entry+="$line"$'\n'
done <"$src"

if [ -f "$dest" ] && [ "$(cat -- "$dest"; echo x)" = "${entry}x" ]; then
    echo "spotify: $dest is current"
    exit 0
fi
if $dry; then
    echo "spotify: would write $dest (Exec -> scripts/spotify/launch.sh)"
    exit 0
fi
mkdir -p "$apps"
printf '%s' "$entry" >"$dest"
echo "spotify: wrote $dest (Exec -> scripts/spotify/launch.sh)"
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$apps" 2>/dev/null || true
fi
