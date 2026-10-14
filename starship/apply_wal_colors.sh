#!/bin/bash
#
# Render the starship prompt config with the matugen palette substituted in.
#
# starship has no include mechanism and no way to point one config at another,
# so the whole file is templated: starship/starship.toml.in holds the real
# content with @role_<name>@ tokens, and ~/.config/starship.toml is a
# symlink to the copy rendered here. No tracked file changes at runtime.
#
# There is nothing to reload — starship re-reads its config on every prompt,
# so an open shell picks up a new wallpaper's colors at the next prompt.
#

set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
template="$config_dir/starship/starship.toml.in"
rendered="$cache_dir/starship.toml"

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

exit 0
