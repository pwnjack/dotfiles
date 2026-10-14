#!/bin/bash
# The one place a palette is generated: wall.sh and install.sh call this,
# and neither names matugen. Options in <config>/options/: theme-scheme
# (scheme-tonal-spot), theme-contrast (0), theme-prefer (saturation).
# Matugen renders no templates, running --dry-run --json hex in a scratch cwd.
# --fallback-color is the fallback palette's seed for flat/near-grey images.
# On failure nothing is replaced; conversion finishes before publication.
set -euo pipefail

if ! command -v matugen >/dev/null 2>&1; then
    echo 'generate-palette: matugen is not installed' >&2
    exit 1
fi
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo 'Usage: generate-palette.sh <image> [out-dir]' >&2
    exit 1
fi
config="${XDG_CONFIG_HOME:-$HOME/.config}"
image=$1
default_out="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
out="${2:-$default_out}"
# Matugen runs elsewhere, so relative paths must be resolved before cd.
[[ "$image" = /* ]] || image="$PWD/$image"
[[ "$config" = /* ]] || config="$PWD/$config"
[[ "$out" = /* ]] || out="$PWD/$out"
scratch=''
stage=''
trap 'rm -rf -- "$scratch" "$stage"' EXIT
trap 'echo "generate-palette: palette generation failed" >&2; exit 1' ERR

read_option() {
    local name=$1 default=$2 pattern=$3 value
    local file="$config/options/$name"
    if [ ! -f "$file" ]; then
        printf '%s' "$default"
        return
    fi
    value=$(cat -- "$file")
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if [[ "$value" =~ $pattern ]]; then
        printf '%s' "$value"
    else
        printf 'generate-palette: invalid %s; using %s\n' "$file" "$default" >&2
        printf '%s' "$default"
    fi
}
scheme=$(read_option theme-scheme scheme-tonal-spot '^scheme-(content|expressive|fidelity|fruit-salad|monochrome|neutral|rainbow|tonal-spot|vibrant)$')
contrast=$(read_option theme-contrast 0 '^-?(0(\.[0-9]+)?|1(\.0+)?)$')
prefer=$(read_option theme-prefer saturation '^(darkness|lightness|saturation|less-saturation|value|closest-to-fallback)$')

scratch=$(mktemp -d)
if ! (cd "$scratch" && timeout -k 5 "${GENERATE_TIMEOUT:-30}" matugen image "$image" -c "$config/matugen/config.toml" \
    -m dark -t "$scheme" --contrast "$contrast" --prefer "$prefer" \
    --fallback-color '#6097a1' --dry-run --json hex -q > "$scratch/matugen.json"); then
    echo "generate-palette: matugen failed for $image" >&2
    exit 1
fi
mkdir -p -- "$out"
stage=$(mktemp -d "$out/.generate.XXXXXX")
if ! bash "$config/scripts/theming/matugen-to-wal.sh" "$scratch/matugen.json" "$stage"; then
    echo 'generate-palette: palette conversion failed' >&2
    exit 1
fi
# Standalone generation shares wall.sh's publication lock. Its explicit
# staging directory must never take the lock that wall.sh already holds.
if [ "$out" -ef "$default_out" ]; then
    exec 9>"$out/wallpaper.lock"
    flock -w 30 9 || { echo 'generate-palette: timed out waiting for wallpaper.lock' >&2; exit 1; }
fi
# Reject non-file targets before replacing either member of the palette.
for name in colors roles; do
    if { [ -e "$out/$name" ] || [ -L "$out/$name" ]; } && [ ! -f "$out/$name" ]; then
        echo "generate-palette: cannot replace $out/$name: not a regular file" >&2
        exit 1
    fi
done
# Same-filesystem renames publish complete files. If the second fails, restore
# the first. Publish roles before colors, matching wall.sh's order.
had_roles=0
if [ -e "$out/roles" ]; then
    cp -pP -- "$out/roles" "$stage/roles.before"
    had_roles=1
fi
mv -fT -- "$stage/roles" "$out/roles"
if ! mv -fT -- "$stage/colors" "$out/colors"; then
    if [ "$had_roles" -eq 1 ]; then
        mv -fT -- "$stage/roles.before" "$out/roles"
    else
        rm -f -- "$out/roles"
    fi
    echo 'generate-palette: palette publication failed' >&2
    exit 1
fi
