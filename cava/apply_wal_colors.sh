#!/bin/bash
#
# Render cava's config with the matugen palette substituted in.
#
# cava has a theme mechanism (`theme = '<name>'` reading cava's themes directory),
# which would have been the natural fit here. It is unusable: cava 0.10.7
# corrupts the heap and aborts with "free(): invalid next size" on any vertical
# `gradient`, in a theme file or in the main config, at every stop count.
# Its own bundled themes/solarized_dark crashes it the same way, so this is
# upstream. horizontal_gradient is unaffected and is what the template uses.
#
# So the whole config is templated instead: cava/config.in holds the real
# content with @role_<name>@ tokens, and cava/config is a symlink to the rendered
# copy in the cache. No tracked file changes at runtime.
#

set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
template="$config_dir/cava/config.in"
rendered="$cache_dir/cava-config"

[ -r "$template" ] || exit 0

# shellcheck disable=SC2034  # read by wal_render from palette.sh
declare -a wal=()
# shellcheck source=scripts/theming/palette.sh
. "$config_dir/scripts/theming/palette.sh"
wal_load
# shellcheck disable=SC2034  # read by role_load and wal_render
declare -A role=()
role_load

mkdir -p "$cache_dir"

wal_render "$template" "$rendered"

# Colors-only reload for any running cava. SIGUSR1 would reload the whole
# config, which also reinitialises audio capture.
pkill -USR2 -x cava 2>/dev/null

exit 0
