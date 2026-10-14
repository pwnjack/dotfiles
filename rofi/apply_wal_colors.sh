#!/bin/bash
#
# Render the matugen palette as rofi color variables.
#
# rofi/options/colors.rasi is a tracked symlink to the file written here, and
# every rofi theme imports it. Rendering it from the shared loader, rather than
# from a generator template, keeps it existing on a fresh checkout where
# matugen has never run and no template is installed.
#
# The themes override background/selected with literals, so only foreground
# and border show.
#
# rofi reads its theme on every launch, so there is nothing to reload.
#

set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/wal"

declare -a wal=()
# shellcheck source=scripts/theming/palette.sh
. "$config_dir/scripts/theming/palette.sh"
wal_load
# shellcheck disable=SC2034  # read by role_load and wal_role
declare -A role=()
role_load

mkdir -p "$cache_dir"

cat > "$cache_dir/colors-rofi.rasi" <<EOF
* {
    background: ${wal[0]}CC;
    foreground: ${wal[7]};
    selected:   $(wal_role secondary_container)66;
    border:     ${wal[7]}CC;
    accent:     $(wal_role primary);
    accentlow:  $(wal_role primary)66;
}
EOF
