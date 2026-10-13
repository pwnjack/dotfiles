#!/bin/bash
#
# Every cache-rendering apply script must produce its output from the fallback
# palette when pywal has never run: the repo tracks symlinks to these files,
# and a dangling one is a doctor ERROR on a fresh checkout.
#
# swaync only reloads a live consumer and renders nothing, so it is not run;
# nvim is the same kind and is tested separately below.
# pkill, hyprctl, spicetify and eww are stubbed so no running cava, Hyprland,
# Spotify or eww daemon is touched.
#

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/cache" "$tmp/home"
for stub in pkill hyprctl spicetify eww; do
    printf '#!/bin/sh\nexit 1\n' > "$tmp/bin/$stub"
    chmod +x "$tmp/bin/$stub"
done

# shellcheck source=scripts/lib/assert.sh
. "$ROOT/scripts/lib/assert.sh"

# component script -> the cache file its tracked symlink points at
declare -A outputs=(
    [rofi]=colors-rofi.rasi
    [ghostty]=ghostty-colors
    [Thunar]=thunar-gtk.css
    [strata]=strata-theme.toml
    [cava]=cava-config
    [starship]=starship.toml
    [btop]=btop.theme
    [waybar]=colors-waybar.css
    [hypr]=colors-hyprland.lua
    [vesktop]=vesktop.theme.css
    [zen]=zen-userChrome.css
    [spicetify]=spicetify-color.ini
    [eww]=eww-colors.scss
)

# shellcheck source=scripts/theming/palette.sh
. "$ROOT/scripts/theming/palette.sh"
declare -a wal=()
XDG_CACHE_HOME="$tmp/cache" wal_load   # empty cache: the fallback palette

uses_palette() {
    local color
    for color in "${wal[@]}"; do
        grep -qiF "${color#\#}" "$1" && return 0
    done
    return 1
}

for component in "${!outputs[@]}"; do
    out="$tmp/cache/wal/${outputs[$component]}"
    # HOME too: zen's script links into the browser profile under ~/.zen, and
    # must never point a real profile at this temporary cache.
    if ! PATH="$tmp/bin:$PATH" HOME="$tmp/home" XDG_CONFIG_HOME="$ROOT" XDG_CACHE_HOME="$tmp/cache" \
        "$ROOT/$component/apply_wal_colors.sh" >/dev/null 2>&1; then
        fail "$component/apply_wal_colors.sh exits nonzero with no pywal cache"
    elif [ ! -s "$out" ]; then
        fail "$component/apply_wal_colors.sh leaves ${outputs[$component]} missing or empty"
    elif grep -q '@[a-z]*color[0-9]*@' "$out"; then
        fail "$component/apply_wal_colors.sh leaves unreplaced @color@ tokens"
    elif ! uses_palette "$out"; then
        fail "$component/apply_wal_colors.sh does not use the fallback palette"
    else
        pass "$component renders ${outputs[$component]} from the fallback palette"
    fi
done

# Strata loads a complete TOML theme at startup. Check its exact schema,
# unchanged-cache behaviour, and every readable pairing on extreme and
# mid-tone palettes, including colour0 values that used to defeat contrast.
strata_theme="$tmp/cache/wal/strata-theme.toml"
strata_stamp=$(stat -c '%y' "$strata_theme")
HOME="$tmp/home" XDG_CONFIG_HOME="$ROOT" XDG_CACHE_HOME="$tmp/cache" \
    bash "$ROOT/strata/apply_wal_colors.sh"
assert_eq "$?" 0 "Strata rerender succeeds"
assert_eq "$(stat -c '%y' "$strata_theme")" "$strata_stamp" "an unchanged Strata palette leaves the cache untouched"
strata_themes=("$strata_theme")
for background in '#05090c' '#f4f4f4' '#808080' '#777777' '#556677' '#a0a0a0'; do
    palette_cache="$tmp/${background#\#}"
    mkdir -p "$palette_cache/wal"
    for ((i = 0; i < 16; i++)); do
        case "$i" in
            0) echo "$background" ;;
            7) echo '#101010' ;;
            15) echo '#ffffff' ;;
            *) echo '#789abc' ;;
        esac
    done > "$palette_cache/wal/colors"
    HOME="$tmp/home" XDG_CONFIG_HOME="$ROOT" XDG_CACHE_HOME="$palette_cache" \
        bash "$ROOT/strata/apply_wal_colors.sh"
    assert_eq "$?" 0 "Strata renders background $background"
    strata_themes+=("$palette_cache/wal/strata-theme.toml")
done
python3 - "${strata_themes[@]}" <<'PY_CONTRAST'
import re, sys, tomllib

syntax = ['syntax_keyword', 'syntax_string', 'syntax_constant', 'syntax_type', 'syntax_preprocessor']
keys = {'background', 'surface', 'text', 'accent', 'danger', 'muted', 'highlight', 'border', 'dim_text', *syntax}

def luminance(hex_colour):
    channels = [int(hex_colour[i:i+2], 16) / 255 for i in (1, 3, 5)]
    linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return sum(c * w for c, w in zip(linear, (0.2126, 0.7152, 0.0722)))

for path in sys.argv[1:]:
    with open(path, 'rb') as source:
        colours = tomllib.load(source)
    if set(colours) != keys | {'name'} or colours['name'] != 'Pywal':
        sys.exit(f'{path}: expected name = "Pywal" and exactly 14 colour keys')
    for key in keys:
        if not re.fullmatch(r'#[0-9a-fA-F]{6}', colours[key]):
            sys.exit(f'{path}: {key} is not a #rrggbb colour')
    pairs = [(fg, bg) for fg in ['text', 'dim_text', 'danger', 'accent', *syntax]
             for bg in ['background', 'surface']]
    pairs += [('text', bg) for bg in ['highlight', 'muted']]
    for foreground, surface in pairs:
        values = sorted([luminance(colours[foreground]), luminance(colours[surface])])
        ratio = (values[1] + 0.05) / (values[0] + 0.05)
        if ratio < 4.5:
            sys.exit(f'{path}: {foreground} on {surface} contrast {ratio:.2f} < 4.5')
PY_CONTRAST
assert_eq "$?" 0 "Strata has a complete hex TOML theme and readable contrast on dark, light and mid-tone palettes"

# wal_render must substitute @color15@ before @color1@, which is its prefix.
printf '@color1@ @color15@ @oncolor0@\n' > "$tmp/template"
wal_render "$tmp/template" "$tmp/rendered"
expected="${wal[1]} ${wal[15]} $(wal_readable_on "${wal[0]}")"
if [ "$(cat "$tmp/rendered")" = "$expected" ]; then
    pass "wal_render substitutes prefix-overlapping tokens correctly"
else
    fail "wal_render produced '$(cat "$tmp/rendered")', expected '$expected'"
fi

# wal_oklch is the hex form of the CSS themes' OKLCH clamp: unclamped it must
# round-trip, and clamped it must hold a light colour inside the dark band.
if [ "$(wal_oklch '#6097A1' 0 1 1)" = "#6097a1" ] && [ "$(wal_oklch '#05090c' 0 1 1)" = "#05090c" ]; then
    pass "wal_oklch round-trips a colour it does not clamp"
else
    fail "wal_oklch changed an unclamped colour"
fi
if [ "$(wal_oklch '#ffffff' 0.21 0.26 0.04)" = "#242424" ] \
    && [ "$(wal_oklch '#05090c' 0.21 0.26 0.04)" = "#14191d" ] \
    && [ "$(wal_oklch '#05090c' 0.21 0.26 0.04 -0.04)" = "#0b1013" ]; then
    pass "wal_oklch clamps lightness and chroma, then applies the offset"
else
    fail "wal_oklch clamped to unexpected values"
fi

# nvim renders nothing (pywal writes colors-wal.vim itself); its script only
# asks running instances to re-apply. It must exit 0 whether nvim is missing,
# or an instance's socket is stale and every request fails.
mkdir -p "$tmp/run" "$tmp/nobin"
python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$tmp/run/nvim.123.0"
printf '#!/bin/sh\necho "$@" >> "%s"\nexit 1\n' "$tmp/nvim-calls" > "$tmp/bin/nvim"
chmod +x "$tmp/bin/nvim"
if PATH="$tmp/bin:$PATH" XDG_RUNTIME_DIR="$tmp/run" "$ROOT/nvim/apply_wal_colors.sh" \
    && grep -q -- "--server $tmp/run/nvim.123.0 --remote-expr" "$tmp/nvim-calls"; then
    pass "nvim asks each running instance to re-apply, and a failed request is not a failure"
else
    fail "nvim/apply_wal_colors.sh failed, or never addressed the instance's socket"
fi
for cmd in bash timeout id; do ln -sf "$(command -v "$cmd")" "$tmp/nobin/$cmd"; done
if PATH="$tmp/nobin" XDG_RUNTIME_DIR="$tmp/run" "$tmp/nobin/bash" "$ROOT/nvim/apply_wal_colors.sh"; then
    pass "nvim/apply_wal_colors.sh is a no-op without nvim"
else
    fail "nvim/apply_wal_colors.sh exits nonzero without nvim"
fi

test_summary theming
