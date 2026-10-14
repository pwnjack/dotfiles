#!/bin/bash
#
# Render the matugen palette as a custom Strata theme.
# strata/themes/tokyo-night.toml links to this cache file, replacing the bundled
# default so fresh Strata installs use the palette without setup. Users can
# still pick another theme in Strata. Themes are read only at startup: open
# windows and an idle --portal chooser (about two minutes) keep the old palette.
# Always render the cache, even without Strata installed; no app is launched.

set -euo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
rendered="$cache_dir/strata-theme.toml"

declare -a wal=()
# shellcheck source=scripts/theming/palette.sh disable=SC1091
. "$config_dir/scripts/theming/palette.sh"
wal_load
# shellcheck disable=SC2034  # read by role_load, wal_role and wal_render
declare -A role=()
role_load

# Keep the base in a dark or light band, like the Vesktop and Zen clamps,
# rather than trusting a mid-tone wallpaper colour to support readable text.
if [ "$(wal_readable_on "${wal[0]}")" = "${wal[15]}" ]; then
    bg=$(wal_oklch "${wal[0]}" 0.21 0.26 0.04)
else
    bg=$(wal_oklch "${wal[0]}" 0.92 0.98 0.04)
fi
# Choose foregrounds from the clamped base. All foreground clamps allow at
# least 4.5:1 on both base and surface; text also clears muted and highlight.
if [ "$(wal_readable_on "$bg")" = "${wal[15]}" ]; then
    surface=$(wal_oklch "$bg" 0 1 0.04 0.04)
    muted=$(wal_oklch "$bg" 0 1 0.04 0.06)
    highlight=$(wal_oklch "$bg" 0 1 0.04 0.09)
    border=$(wal_oklch "$bg" 0 1 0.04 0.12)
    text=$(wal_oklch "${wal[7]}" 0.85 1 0.05)
    dim_text=$(wal_oklch "$(wal_readable_on "$bg")" 0.72 0.78 0.04)
    foreground() { wal_oklch "$1" 0.76 0.84 0.12; }
else
    surface=$(wal_oklch "$bg" 0 1 0.04 -0.04)
    muted=$(wal_oklch "$bg" 0 1 0.04 -0.06)
    highlight=$(wal_oklch "$bg" 0 1 0.04 -0.09)
    border=$(wal_oklch "$bg" 0 1 0.04 -0.12)
    text=$(wal_oklch "${wal[7]}" 0 0.20 0.05)
    dim_text=$(wal_oklch "$(wal_readable_on "$bg")" 0.30 0.38 0.04)
    foreground() { wal_oklch "$1" 0.30 0.38 0.12; }
fi
accent=$(foreground "$(wal_role primary)")
# Keep destructive actions recognisably red even on a monochrome palette.
danger=$(foreground '#e26f7c')
syntax_keyword=$(foreground "${wal[5]}")
syntax_string=$(foreground "${wal[2]}")
syntax_constant=$(foreground "${wal[9]}")
syntax_type=$(foreground "${wal[3]}")
syntax_preprocessor=$(foreground "${wal[6]}")

mkdir -p "$cache_dir"
temporary=$(mktemp "$rendered.XXXXXX")
trap 'rm -f -- "$temporary"' EXIT
publish() {
    cmp -s "$temporary" "$rendered" || mv -f -- "$temporary" "$rendered"
}
cat > "$temporary" <<EOF_THEME && publish
# Generated from the matugen palette - do not edit manually.
name = "Wallpaper"
background = "$bg"
surface = "$surface"
text = "$text"
accent = "$accent"
danger = "$danger"
muted = "$muted"
highlight = "$highlight"
border = "$border"
dim_text = "$dim_text"
syntax_keyword = "$syntax_keyword"
syntax_string = "$syntax_string"
syntax_constant = "$syntax_constant"
syntax_type = "$syntax_type"
syntax_preprocessor = "$syntax_preprocessor"
EOF_THEME
