#!/bin/bash
#
# Render the matugen palette as a Vencord theme for Vesktop.
#
# vesktop/pywal.theme.css.in holds the CSS with slot and role tokens. The
# tracked vesktop/themes/pywal.theme.css is a symlink to the copy rendered
# here, so no tracked file changes at runtime. Enable it once in Vesktop under
# Settings > Themes; which themes are on is Vesktop's own state.
#
# A running Vesktop re-reads its themes when its themes directory changes, but
# it watches the directory, not the symlink's target in the cache: writing the
# rendered file alone fires nothing. Touching the symlink itself does, so open
# windows recolour without a restart.
#

set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
template="$config_dir/vesktop/pywal.theme.css.in"
rendered="$cache_dir/vesktop.theme.css"
link="$config_dir/vesktop/themes/pywal.theme.css"

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

if [ -L "$link" ]; then
    touch -h "$link"
fi

exit 0
