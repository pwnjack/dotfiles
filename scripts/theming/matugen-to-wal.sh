#!/bin/bash
# Convert matugen JSON into colors (16 ANSI slots) and roles (name=#rrggbb).
# Slots: surface; red/green/yellow/blue/magenta/cyan; on_surface; outline;
# on_red/green/yellow/blue/magenta/cyan_container; on_surface.
# Optional ANSI JSON supplies only the twelve chromatic terminal slots.
# Surfaces, text and all semantic roles retain the chosen scheme and contrast.
# Bad input never replaces a working palette: validate both before publishing.
set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo 'Usage: matugen-to-wal.sh <matugen.json> <out-dir> [ansi-json]' >&2
    exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
    echo 'matugen-to-wal: jq is required' >&2
    exit 1
fi
json=$1
out=$2
colors_tmp=''
roles_tmp=''
trap 'rm -f -- "$colors_tmp" "$roles_tmp"' EXIT
# Normalize operational failures as well as invalid input to exit 1.
trap 'exit 1' ERR
mkdir -p -- "$out"
colors_tmp=$(mktemp "$out/.colors.XXXXXX")
roles_tmp=$(mktemp "$out/.roles.XXXXXX")
roles=(surface surface_container_low surface_container surface_container_high
       surface_container_highest on_surface on_surface_variant outline outline_variant
       primary on_primary primary_container on_primary_container secondary_container
       on_secondary_container tertiary_container on_tertiary_container error on_error)

jq -er --slurpfile ansi "${3:-$json}" '
  def a($n): ($ansi[0].colors[$n].dark.color // error("missing ANSI \($n)")) | ascii_downcase;
  def c($n): (.colors[$n].dark.color // error("missing \($n)")) | ascii_downcase;
  [ c("surface"),
    a("red"), a("green"), a("yellow"), a("blue"), a("magenta"), a("cyan"),
    c("on_surface"), c("outline"),
    a("on_red_container"), a("on_green_container"), a("on_yellow_container"),
    a("on_blue_container"), a("on_magenta_container"), a("on_cyan_container"),
    c("on_surface") ] | .[]
' "$json" > "$colors_tmp"

# Capture the document before the tone generator changes dot to a tone string.
jq -er --argjson names "$(printf '%s\n' "${roles[@]}" | jq -R . | jq -s .)" '
  . as $d
  | def c($n): ($d.colors[$n].dark.color // error("missing \($n)")) | ascii_downcase;
    ($names[] | "\(.)=\(c(.))"),
    ("30","40","50","60","70","80","90","95" | . as $t
       | "primary_t\($t)=\(($d.palettes.primary[$t].color // error("missing tone \($t)")) | ascii_downcase)")
' "$json" > "$roles_tmp"

if [ "$(wc -l < "$colors_tmp")" -ne 16 ] ||
   [ "$(wc -l < "$roles_tmp")" -ne 27 ] ||
   grep -qEv '^#[0-9a-f]{6}$' "$colors_tmp" ||
   grep -qEv '^[a-z0-9_]+=#[0-9a-f]{6}$' "$roles_tmp"; then
    echo 'matugen-to-wal: invalid palette colors or roles' >&2
    exit 1
fi
chmod 644 "$colors_tmp" "$roles_tmp"
mv -f -- "$colors_tmp" "$out/colors"
mv -f -- "$roles_tmp" "$out/roles"
