#!/bin/bash
#
# Render the matugen palette as the colour scheme of the Pywal Spicetify theme,
# and push it into a patched Spotify client.
#
# The tracked spicetify/Themes/Pywal/color.ini is a symlink to the file written
# here, so no tracked file changes at runtime. Spicetify reads only hex in
# color.ini, so the readability clamps the CSS themes do with relative colours
# are done here with wal_oklch: surfaces stay in the same dark band as Vesktop
# and Zen, the accent at Spotify-green lightness (its black play icon sits on
# it), and text keeps Spotify's own white and grey. The volume and progress
# bars draw their empty part as the text colour at 30%, so filled and empty
# always differ.
#
# `spicetify refresh` copies the colours into the client without restarting
# it, and the pywal-live extension swaps them into a running Spotify. Refresh
# runs only while Pywal is the selected theme (scripts/spotify/spicetify-theme.sh
# selects it once; another choice is left alone), only on a client Spicetify
# has unpacked, and never alongside scripts/spotify/launch.sh's patch run: it
# shares that run's lock. When a patch holds it, a detached waiter refreshes
# once the patch is done, because the patch may already have applied the
# previous colours.
#

set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/spotify"
rendered="$cache_dir/spicetify-color.ini"
spicetify_ini="$config_dir/spicetify/config-xpui.ini"

declare -a wal=()
# shellcheck source=scripts/theming/palette.sh
. "$config_dir/scripts/theming/palette.sh"
wal_load
# shellcheck disable=SC2034  # read by role_load, wal_role and wal_render
declare -A role=()
role_load

mkdir -p "$cache_dir"

# Spicetify wants bare hex, without the '#'.
base() { local c; c=$(wal_oklch "${wal[0]}" 0.21 0.26 0.04 "$1") && printf '%s' "${c#\#}"; }
accent() { local c; c=$(wal_oklch "$(wal_role primary)" 0.62 0.75 0.16 "$1") && printf '%s' "${c#\#}"; }

{
    echo "; Generated from the matugen palette by spicetify/apply_wal_colors.sh - do not edit"
    echo "[pywal]"
    echo "text               = ffffff"
    echo "subtext            = b3b3b3"
    echo "selected-row       = ffffff"
    echo "main               = $(base 0)"
    echo "main-elevated      = $(base 0.03)"
    echo "main-secondary     = $(base 0.05)"
    echo "highlight          = $(base 0.03)"
    echo "highlight-elevated = $(base 0.06)"
    echo "sidebar            = $(base -0.04)"
    echo "player             = $(base -0.04)"
    echo "card               = $(base 0.03)"
    echo "shadow             = 000000"
    echo "nav-active         = $(base 0.06)"
    echo "nav-active-text    = ffffff"
    echo "tab-active         = $(base 0.06)"
    echo "notification       = $(base 0.08)"
    echo "notification-error = e22134"
    echo "misc               = $(base 0.1)"
    echo "button             = $(accent 0)"
    echo "button-active      = $(accent 0.04)"
    echo "button-secondary   = b3b3b3"
    echo "button-disabled    = $(base 0.12)"
    echo "play-button        = $(accent 0)"
    echo "playback-bar       = $(accent 0)"
} > "$rendered.tmp" && mv "$rendered.tmp" "$rendered" || exit 1

command -v spicetify >/dev/null 2>&1 && [ -r "$spicetify_ini" ] || exit 0
grep -qE '^current_theme[[:space:]]*=[[:space:]]*Pywal[[:space:]]*$' "$spicetify_ini" || exit 0

# Refresh needs the client Spicetify unpacked: Apps/xpui, not xpui.spa.
client=$(sed -n 's/^spotify_path[[:space:]]*=[[:space:]]*//p' "$spicetify_ini")
client=${client//\$HOME/$HOME}
client=${client/#\~/$HOME}
[ -d "$client/Apps/xpui" ] && [ ! -e "$client/Apps/xpui.spa" ] || exit 0

mkdir -p "$state_dir"
exec 9>"$state_dir/patch.lock"
if flock -n 9; then
    timeout 60 spicetify -q -n refresh </dev/null >/dev/null
    exit
fi

# A patch run can take minutes; wait for it in the background so the
# wallpaper change is not held up. The waiter's name is bash, which SpotX's
# pkill '[sS]potify' does not match.
setsid bash -c 'flock -w 900 9 && timeout 60 spicetify -q -n refresh' \
    </dev/null >/dev/null 2>&1 &
