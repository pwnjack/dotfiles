#!/bin/bash
#
# Render the matugen palette as Zen's userChrome.css.
#
# zen/userChrome.css.in holds the CSS with slot and role tokens, rendered
# into the wal cache. Zen's profile lives in ~/.zen, outside the repo, so nothing
# tracked points at the result; instead, when Zen is installed, this links the
# profile's chrome/userChrome.css to the rendered file and turns on the pref
# that makes Zen load it. Both steps are idempotent. A userChrome.css that is
# not our link is the user's own and is left alone.
#
# Zen reads userChrome.css at startup only and has no reload request, so a
# running browser keeps its colours until the next launch.
#

set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
template="$config_dir/zen/userChrome.css.in"
rendered="$cache_dir/zen-userChrome.css"
zen_dir="$HOME/.zen"
pref='user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'

[ -r "$template" ] || exit 0

# shellcheck disable=SC2034  # read by wal_render from palette.sh
declare -a wal=()
# shellcheck source=scripts/theming/palette.sh
. "$config_dir/scripts/theming/palette.sh"
wal_load
# shellcheck disable=SC2034  # read by role_load, wal_role and wal_render
declare -A role=()
role_load

mkdir -p "$cache_dir"

wal_render "$template" "$rendered" || exit 1

# The profile Zen launches: its install's Default= in profiles.ini, which can
# differ from the profile marked Default=1. The path is relative to ~/.zen
# unless the profile was created elsewhere, which makes it absolute.
_zen_profile() {
    local ini="$zen_dir/profiles.ini" path
    [ -r "$ini" ] || return 1
    path=$(awk -F= '{ sub(/\r$/, "") } /^\[Install/ { inst = 1; next } /^\[/ { inst = 0 }
                    inst && $1 == "Default" { print substr($0, 9); exit }' "$ini")
    [ -n "$path" ] || return 1
    [ "${path#/}" != "$path" ] || path="$zen_dir/$path"
    [ -d "$path" ] || return 1
    printf '%s\n' "$path"
}

profile=$(_zen_profile) || exit 0

# A link to some other zen-userChrome.css is ours from an earlier cache
# location, so it is re-pointed; anything else is the user's own.
link="$profile/chrome/userChrome.css"
if [ -L "$link" ] && [ "$(readlink "$link")" = "$rendered" ]; then
    :
elif [ -L "$link" ] && [ "$(basename -- "$(readlink "$link")")" = zen-userChrome.css ]; then
    ln -sfn "$rendered" "$link"
elif [ -e "$link" ] || [ -L "$link" ]; then
    echo "zen: $link is not ours; leaving it" >&2
else
    mkdir -p "$profile/chrome"
    ln -s "$rendered" "$link"
fi

userjs="$profile/user.js"
if ! grep -qxF "$pref" "$userjs" 2>/dev/null; then
    # Start on a line of its own when the file does not end in a newline.
    if [ -s "$userjs" ] && [ -n "$(tail -c 1 "$userjs")" ]; then
        echo >> "$userjs"
    fi
    printf '%s\n' "$pref" >> "$userjs"
fi

exit 0
