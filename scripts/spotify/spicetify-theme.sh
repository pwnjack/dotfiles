#!/bin/bash
# Select the Pywal Spicetify theme and its live-recolour extension, once.
#
#   scripts/spotify/spicetify-theme.sh
#
# Spicetify keeps its choices in its own config-xpui.ini, which the repo does
# not track, so this records them there: current_theme Pywal, color_scheme
# pywal, and pywal-live.js among the extensions. Run by install.sh; skipped
# without spicetify or before Spicetify has written its config. Idempotent:
# spicetify itself never lists an extension twice.
#
# It does not apply anything to the client. Spotify's wrapper
# (scripts/spotify/launch.sh) applies the configured theme on its next patch,
# and on an already patched client spicetify/apply_wal_colors.sh's refresh
# does; the extension itself needs one `spicetify apply` and a Spotify
# restart, which this prints.
#
# Its file name must not contain "spotify": SpotX runs pkill '[sS]potify'.
set -euo pipefail

ini="${XDG_CONFIG_HOME:-$HOME/.config}/spicetify/config-xpui.ini"

if ! command -v spicetify >/dev/null 2>&1 || [ ! -r "$ini" ]; then
    echo "spicetify: not set up; skipping the Pywal theme"
    exit 0
fi

extensions=$(sed -n 's/^extensions[[:space:]]*=[[:space:]]*//p' "$ini")
spicetify -q config current_theme Pywal color_scheme pywal extensions pywal-live.js </dev/null

case "|${extensions%"${extensions##*[![:space:]]}"}|" in
    *"|pywal-live.js|"*) ;;
    *) echo "spicetify: Pywal selected; run 'spicetify apply' and restart Spotify once to load pywal-live.js" ;;
esac
