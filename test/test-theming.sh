#!/bin/bash
#
# Every cache-rendering apply script must produce its output from the fallback
# palette when matugen has never run: the repo tracks symlinks to these files,
# and a dangling one is a doctor ERROR on a fresh checkout.
#
# swaync only reloads a live consumer and renders nothing, so it is not run;
# nvim renders its palette here and its reload behaviour is tested below.
# pkill, hyprctl, spicetify, eww and nvim are stubbed so no running cava,
# Hyprland, Spotify, eww daemon or editor is touched.
#

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/cache" "$tmp/home" "$tmp/pts" "$tmp/run"
touch "$tmp/pts/0"
printf 'multiplexer sentinel\n' > "$tmp/pts/ptmx"
for stub in pkill hyprctl spicetify eww nvim; do
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
    [nvim]=colors-wal.vim
)

# shellcheck source=scripts/theming/palette.sh
. "$ROOT/scripts/theming/palette.sh"
declare -a wal=()
XDG_CACHE_HOME="$tmp/cache" wal_load   # empty cache: the fallback palette
declare -A role=()
XDG_CACHE_HOME="$tmp/cache" role_load

uses_palette() {
    local color
    # Spicetify clamps every palette-derived color; none need equal a raw
    # slot. Verify both its base and accent against the loaded fallback.
    if [ "$component" = spicetify ]; then
        local base accent
        base=$(wal_oklch "${wal[0]}" 0.21 0.26 0.04 0)
        accent=$(wal_oklch "$(wal_role primary)" 0.62 0.75 0.16 0)
        grep -qE "^main[[:space:]]*=[[:space:]]*${base#\#}$" "$1" \
            && grep -qE "^button[[:space:]]*=[[:space:]]*${accent#\#}$" "$1"
        return
    fi
    for color in "${wal[@]}" "${role[@]}"; do
        grep -qiF "${color#\#}" "$1" && return 0
    done
    return 1
}

for component in "${!outputs[@]}"; do
    out="$tmp/cache/wal/${outputs[$component]}"
    # HOME too: zen's script links into the browser profile under ~/.zen, and
    # must never point a real profile at this temporary cache.
    if ! PATH="$tmp/bin:$PATH" HOME="$tmp/home" XDG_CONFIG_HOME="$ROOT" XDG_CACHE_HOME="$tmp/cache" XDG_RUNTIME_DIR="$tmp/run" WAL_PTS_DIR="$tmp/pts" \
        "$ROOT/$component/apply_wal_colors.sh" >/dev/null 2>&1; then
        fail "$component/apply_wal_colors.sh exits nonzero with no palette cache"
    elif [ ! -s "$out" ]; then
        fail "$component/apply_wal_colors.sh leaves ${outputs[$component]} missing or empty"
    elif grep -qE '@([a-z]*color[0-9]*|role_[a-z0-9_]+)@' "$out"; then
        fail "$component/apply_wal_colors.sh leaves unreplaced palette tokens"
    elif ! uses_palette "$out"; then
        fail "$component/apply_wal_colors.sh does not use the fallback palette"
    else
        pass "$component renders ${outputs[$component]} from the fallback palette"
    fi
done

# Shared GTK definitions expose semantic surfaces, selections and errors even
# before the first generated palette exists.
waybar_fallback="$(cat "$tmp/cache/wal/colors-waybar.css")"
for name in surface_container surface_container_high secondary_container on_secondary_container error on_error; do
    assert_contains "$waybar_fallback" "@define-color $name $(wal_role "$name");" \
        "Waybar defines fallback $name"
done
if git -C "$ROOT" grep -nE '@color[0-9]' -- swaync; then
    fail "SwayNC still uses ANSI slots for surfaces or selections"
else
    assert_eq "$?" 1 "SwayNC uses semantic roles instead of ANSI slots"
fi

# Every selected fill needs the matching text, including hover/active states
# and translucent fills. Borders alone do not change the text background.
python3 - "$ROOT/swaync/notifications.css" "$ROOT/swaync/central_control.css" <<'PY_SELECTION'
import re, sys
for path in sys.argv[1:]:
    css = open(path).read()
    for selector, declarations in re.findall(r'([^{}]+)\{([^{}]*)\}', css):
        if re.search(r'background(?:-color)?\s*:[^;]*@selected', declarations):
            if not re.search(r'(?<![-\w])color\s*:\s*@on_secondary_container\s*;', declarations):
                sys.exit(f'{path}: {selector.strip()} lacks selection text role')
PY_SELECTION
assert_eq "$?" 0 "SwayNC selected fills use on_secondary_container text"

# Accents use semantic roles independently of ANSI blue, including the
# Material foreground pair in Waybar. Keep the loop's consumer guards here.
accent_cache="$tmp/accent-cache"
mkdir -p "$accent_cache/wal"
printf '#112233\n%.0s' {1..16} > "$accent_cache/wal/colors"
printf 'primary=#0000aa\non_primary=#ffeedd\nsurface_container=#223344\nsurface_container_high=#334455\nsecondary_container=#445566\non_secondary_container=#ddeeff\nerror=#ff9988\non_error=#331100\n' > "$accent_cache/wal/roles"
for component in waybar btop strata rofi Thunar; do
    PATH="$tmp/bin:$PATH" HOME="$tmp/home" XDG_CONFIG_HOME="$ROOT" XDG_CACHE_HOME="$accent_cache" XDG_RUNTIME_DIR="$tmp/run" WAL_PTS_DIR="$tmp/pts" \
        bash "$ROOT/$component/apply_wal_colors.sh"
    assert_eq "$?" 0 "$component renders with a primary distinct from slot 4"
done
waybar_css="$(cat "$accent_cache/wal/colors-waybar.css")"
assert_contains "$waybar_css" '@define-color color4 #112233;' "Waybar preserves ANSI blue"
assert_contains "$waybar_css" '@define-color accent #0000aa;' "Waybar accent follows primary"
assert_contains "$waybar_css" '@define-color on_accent #ffeedd;' "Waybar accent text follows on_primary"
assert_contains "$waybar_css" $'@define-color color15 #112233;\n@define-color accent #0000aa;\n@define-color on_accent #ffeedd;' \
    "Waybar appends role definitions after the slots"
btop_theme="$(cat "$accent_cache/wal/btop.theme")"
for key in hi_fg followed_bg cpu_box; do
    assert_contains "$btop_theme" "theme[$key]=\"#0000aa\"" "btop $key follows primary"
done
for entry in surface_container=#223344 surface_container_high=#334455 secondary_container=#445566 on_secondary_container=#ddeeff error=#ff9988 on_error=#331100; do
    assert_contains "$waybar_css" "@define-color ${entry%=*} ${entry#*=};" "Waybar follows cached ${entry%=*}"
done
assert_contains "$btop_theme" 'theme[selected_bg]="#445566"' "btop selection uses secondary_container"
assert_contains "$btop_theme" 'theme[selected_fg]="#ddeeff"' "btop selection text uses on_secondary_container"
assert_contains "$btop_theme" 'theme[proc_pause_bg]="#ff9988"' "btop pause uses error"
rofi_colors="$(cat "$accent_cache/wal/colors-rofi.rasi")"
assert_contains "$rofi_colors" 'selected:   #44556666;' "Rofi selection uses translucent secondary_container"
assert_contains "$rofi_colors" 'accent:     #0000aa;' "Rofi accent uses primary"
assert_contains "$rofi_colors" 'accentlow:  #0000aa66;' "Rofi low accent uses translucent primary"
thunar_css="$(cat "$accent_cache/wal/thunar-gtk.css")"
assert_contains "$thunar_css" $'background-color: #445566;\n    color: #ddeeff;' "Thunar selection uses the container pair"
assert_contains "$thunar_css" 'background-color: #334455;' "Thunar rubberband uses surface_container_high"
strata_accent=$(wal_oklch '#0000aa' 0.76 0.84 0.12)
assert_contains "$(cat "$accent_cache/wal/strata-theme.toml")" "accent = \"$strata_accent\"" \
    "Strata accent follows primary with its foreground clamp"

# Decorative fills and ramps must follow roles even when ANSI slots differ.
ramp_cache="$tmp/ramp-cache"
mkdir -p "$ramp_cache/wal"
printf '#112233\n%.0s' {1..16} > "$ramp_cache/wal/colors"
ramp_index=0
for name in primary on_primary primary_container on_primary_container secondary_container on_secondary_container tertiary_container on_tertiary_container surface_container_highest on_surface surface_container_high on_surface_variant primary_t30 primary_t40 primary_t50 primary_t60 primary_t70 primary_t80 primary_t90 primary_t95; do
    printf '%s=#%06x\n' "$name" "$((++ramp_index))"
done > "$ramp_cache/wal/roles"
XDG_CACHE_HOME="$ramp_cache" role_load
for component in starship cava btop; do
    PATH="$tmp/bin:$PATH" HOME="$tmp/home" XDG_CONFIG_HOME="$ROOT" XDG_CACHE_HOME="$ramp_cache" XDG_RUNTIME_DIR="$tmp/run" WAL_PTS_DIR="$tmp/pts" \
        bash "$ROOT/$component/apply_wal_colors.sh"
    assert_eq "$?" 0 "$component renders decorative roles independently of ANSI slots"
done
python3 - "$ramp_cache/wal/starship.toml" "$ramp_cache/wal/roles" <<'PY_STARSHIP'
import sys, tomllib
config = tomllib.load(open(sys.argv[1], 'rb'))
roles = dict(line.strip().split('=') for line in open(sys.argv[2]))
pairs = [
    ('primary', 'on_primary', ['username', 'python']),
    ('primary_container', 'on_primary_container', ['directory']),
    ('secondary_container', 'on_secondary_container', ['git_branch', 'git_status']),
    ('tertiary_container', 'on_tertiary_container', ['c', 'elixir', 'elm', 'golang', 'haskell', 'java', 'julia', 'nodejs', 'nim', 'rust']),
    ('surface_container_highest', 'on_surface', ['docker_context']),
    ('surface_container_high', 'on_surface_variant', ['os', 'cmd_duration', 'time']),
]
for bg, fg, modules in pairs:
    for module in modules:
        for key in (['style_user', 'style_root'] if module == 'username' else ['style']):
            assert set(config[module][key].split()) == {f'bg:{roles[bg]}', f'fg:{roles[fg]}'}, (module, key)
backgrounds = [roles[pair[0]] for pair in pairs]
assert f'[ ]({backgrounds[0]})' in config['format']
assert f'[ ]({backgrounds[-1]})' in config['format']
for left, right in zip(backgrounds, backgrounds[1:]):
    assert any(f'[]({style})' in config['format'] for style in [f'fg:{left} bg:{right}', f'bg:{right} fg:{left}'])
assert f'[ ]({backgrounds[-1]})' in config['right_format']
assert f'[ ]({backgrounds[-1]})' in config['right_format']
PY_STARSHIP
assert_eq "$?" 0 "Starship segments, text and separators use matching semantic roles"
cava_text="$(cat "$ramp_cache/wal/cava-config")"
stop=0
for tone in 30 40 50 60 70 80 90 95; do
    assert_contains "$cava_text" "horizontal_gradient_color_$((++stop)) = '$(wal_role "primary_t$tone")'" \
        "cava stop $stop follows primary t$tone"
done
btop_text="$(cat "$ramp_cache/wal/btop.theme")"
for ramp in 'temp 40 60 80' 'cpu 40 60 90' 'free 30 50 70' 'cached 50 70 90' 'available 40 70 95' 'used 60 80 95' 'download 40 60 80' 'upload 50 70 90' 'process 40 60 90'; do
    # shellcheck disable=SC2034  # read indirectly through ${!point} below
    read -r meter start mid end <<< "$ramp"
    for point in start mid end; do
        tone=${!point}
        assert_contains "$btop_text" "theme[${meter}_${point}]=\"$(wal_role "primary_t$tone")\"" \
            "btop $meter $point follows primary t$tone"
    done
done
# Restore fallback roles for the remaining component checks.
XDG_CACHE_HOME="$tmp/cache" role_load

# Neovim consumes the exact Vim variable layout, including all 16 slots.
nvim_palette="$tmp/cache/wal/colors-wal.vim"
nvim_text="$(cat "$nvim_palette" 2>/dev/null || true)"
assert_contains "$nvim_text" '" Special' "nvim palette has the special section"
assert_contains "$nvim_text" 'let wallpaper = ""' "nvim uses an empty wallpaper when none is selected"
assert_contains "$nvim_text" "let background = \"${wal[0]}\"" "nvim background uses fallback slot 0"
assert_contains "$nvim_text" "let foreground = \"${wal[7]}\"" "nvim foreground uses fallback slot 7"
assert_contains "$nvim_text" "let cursor = \"${wal[7]}\"" "nvim cursor uses fallback slot 7"
assert_contains "$nvim_text" '" Colors' "nvim palette has the colors section"
for ((i = 0; i < 16; i++)); do
    assert_contains "$nvim_text" "let color$i = \"${wal[$i]}\"" "nvim fallback color$i matches the palette"
done

# A generated palette replaces every fallback slot; the wallpaper is resolved
# from the cache symlink, with paths safely quoted for Vim.
mkdir -p "$tmp/nvim-cache/wal"
printf '#ABCDEF\n%.0s' {1..16} > "$tmp/nvim-cache/wal/colors"
nvim_wallpaper="$tmp/home/wallpaper "$'\n\r'"\\\"quoted\".png"
touch "$nvim_wallpaper"
ln -s "$nvim_wallpaper" "$tmp/nvim-cache/current_wallpaper"
PATH="$tmp/bin:$PATH" HOME="$tmp/home" XDG_CONFIG_HOME="$ROOT" XDG_CACHE_HOME="$tmp/nvim-cache" XDG_RUNTIME_DIR="$tmp/run" WAL_PTS_DIR="$tmp/pts" \
    bash "$ROOT/nvim/apply_wal_colors.sh"
assert_eq "$?" 0 "nvim renders a cached palette and wallpaper"
nvim_text="$(cat "$tmp/nvim-cache/wal/colors-wal.vim" 2>/dev/null || true)"
assert_contains "$nvim_text" "let wallpaper = \"$tmp/home/wallpaper \\\\\\\"quoted\\\".png\"" \
    "nvim resolves the wallpaper symlink, strips LF/CR, and escapes backslashes and quotes"
assert_eq "$(printf '%s\n' "$nvim_text" | wc -l)" 23 \
    "nvim wallpaper control characters do not introduce extra Vim lines"
for ((i = 0; i < 16; i++)); do
    assert_contains "$nvim_text" "let color$i = \"#abcdef\"" "nvim cached color$i is lowercase"
done
assert_contains "$nvim_text" 'let background = "#abcdef"' "nvim uses the cached background"
assert_contains "$nvim_text" 'let foreground = "#abcdef"' "nvim uses the cached foreground"
assert_contains "$nvim_text" 'let cursor = "#abcdef"' "nvim uses the cached cursor"
PATH="$tmp/bin:$PATH" HOME="$tmp/home" XDG_CONFIG_HOME="$ROOT" XDG_CACHE_HOME="$tmp/nvim-cache" XDG_RUNTIME_DIR="$tmp/run" WAL_PTS_DIR="$tmp/pts" \
    bash "$ROOT/nvim/apply_wal_colors.sh"
assert_eq "$(cat "$tmp/nvim-cache/wal/colors-wal.vim")" "$nvim_text" "nvim rerender is byte-identical"

# Reset old terminal colour overrides so Ghostty's reloaded palette can show.
# Use fake ptys in every invocation, including the component loop above.
: > "$tmp/pts/0"
PATH="$tmp/bin:$PATH" HOME="$tmp/home" XDG_CONFIG_HOME="$ROOT" XDG_CACHE_HOME="$tmp/cache" XDG_RUNTIME_DIR="$tmp/run" WAL_PTS_DIR="$tmp/pts" \
    bash "$ROOT/ghostty/apply_wal_colors.sh"
assert_eq "$?" 0 "Ghostty reload succeeds even when no instance is running"
printf '\033]104\033\\\033]110\033\\\033]111\033\\\033]112\033\\' > "$tmp/pty-reset"
if cmp -s "$tmp/pty-reset" "$tmp/pts/0"; then
    pass "Ghostty clears palette, foreground, background and cursor overrides with exact OSC bytes"
else
    fail "Ghostty did not write the exact OSC reset sequence to the owned pty"
fi
printf 'multiplexer sentinel\n' > "$tmp/ptmx-expected"
if cmp -s "$tmp/ptmx-expected" "$tmp/pts/ptmx"; then
    pass "Ghostty leaves ptmx untouched"
else
    fail "Ghostty wrote terminal resets to ptmx"
fi

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
    if set(colours) != keys | {'name'} or colours['name'] != 'Wallpaper':
        sys.exit(f'{path}: expected name = "Wallpaper" and exactly 14 colour keys')
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

# Slots and semantic roles fall back independently until matugen first runs.
role_cache="$tmp/role-cache"
mkdir -p "$role_cache/wal"
XDG_CACHE_HOME="$role_cache" wal_load
XDG_CACHE_HOME="$role_cache" role_load
assert_eq "$(wal_role primary)" '#82d3e1' "empty cache uses the fallback primary role"
assert_eq "$(wal_role surface)" '#0e1416' "empty cache uses the fallback surface role"
assert_eq "${wal[1]}" '#ffb2bd' "empty cache uses the matugen fallback ANSI red"
assert_eq "${#role[@]}" 27 "role_load supplies all 27 fixed roles"
assert_eq "$(wal_role primary_t95)" '#d1f7ff' "role_load supplies fallback primary tones"

# Existing slot palettes remain usable during an upgrade without a roles file.
printf '#123456\n%.0s' {1..16} > "$role_cache/wal/colors"
XDG_CACHE_HOME="$role_cache" wal_load
XDG_CACHE_HOME="$role_cache" role_load
assert_eq "${wal[1]}" '#123456' "wal_load reads cached slots without roles"
assert_eq "$(wal_role primary)" '#82d3e1' "a slots-only cache keeps fallback roles"
assert_eq "$(wal_role surface)" '#0e1416' "a slots-only cache keeps the fallback surface"

printf '%s\n' 'primary=#123456' 'not a role line' 'surface=#ZZZZZZ' \
    'unknown_name=#abcdef' 'on_surface=#ABCDEF' 'outline=#1234567' \
    'primary_t30=#654321' > "$role_cache/wal/roles"
XDG_CACHE_HOME="$role_cache" role_load
assert_eq "$(wal_role primary)" '#123456' "valid cached roles override the fallback"
assert_eq "$(wal_role surface)" '#0e1416' "invalid cached roles retain the fallback"
assert_eq "${role[unknown_name]+present}" '' "unknown cached roles are ignored"
assert_eq "$(wal_role on_surface)" '#dee3e5' "cached roles require lowercase hex"
assert_eq "$(wal_role outline)" '#899294' "cached roles require exactly six hex digits"
assert_eq "$(wal_role primary_t30)" '#654321' "cached primary tones override the fallback"
assert_eq "${#role[@]}" 27 "malformed role lines do not add names"

printf '@role_primary@ @role_primary_container@ @color1@\n' > "$tmp/role-template"
wal_render "$tmp/role-template" "$tmp/role-rendered"
assert_eq "$(cat "$tmp/role-rendered")" '#123456 #004f58 #123456' \
    "wal_render substitutes role tokens and slots without prefix collisions"

# Reloading reseeds roles rather than retaining overrides from an earlier load.
printf 'surface=#112233\n' > "$role_cache/wal/roles"
XDG_CACHE_HOME="$role_cache" role_load
assert_eq "$(wal_role primary)" '#82d3e1' "role_load resets roles missing from the next cache"
assert_eq "$(wal_role surface)" '#112233' "role_load reads the next cache"

# nvim renders colors-wal.vim and asks running instances to re-apply.
# It must exit 0 whether nvim is missing,
# or an instance's socket is stale and every request fails.
mkdir -p "$tmp/run" "$tmp/nobin"
python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$tmp/run/nvim.123.0"
printf '#!/bin/sh\necho "$@" >> "%s"\nexit 1\n' "$tmp/nvim-calls" > "$tmp/bin/nvim"
chmod +x "$tmp/bin/nvim"
if PATH="$tmp/bin:$PATH" HOME="$tmp/home" XDG_CONFIG_HOME="$ROOT" XDG_CACHE_HOME="$tmp/cache" XDG_RUNTIME_DIR="$tmp/run" WAL_PTS_DIR="$tmp/pts" "$ROOT/nvim/apply_wal_colors.sh" \
    && grep -q -- "--server $tmp/run/nvim.123.0 --remote-expr" "$tmp/nvim-calls"; then
    pass "nvim asks each running instance to re-apply, and a failed request is not a failure"
else
    fail "nvim/apply_wal_colors.sh failed, or never addressed the instance's socket"
fi
for cmd in bash timeout id mkdir mv readlink; do ln -sf "$(command -v "$cmd")" "$tmp/nobin/$cmd"; done
mkdir -p "$tmp/no-nvim-cache"
if PATH="$tmp/nobin" HOME="$tmp/home" XDG_CONFIG_HOME="$ROOT" XDG_CACHE_HOME="$tmp/no-nvim-cache" XDG_RUNTIME_DIR="$tmp/run" WAL_PTS_DIR="$tmp/pts" "$tmp/nobin/bash" "$ROOT/nvim/apply_wal_colors.sh"; then
    pass "nvim/apply_wal_colors.sh succeeds without nvim"
else
    fail "nvim/apply_wal_colors.sh exits nonzero without nvim"
fi

assert_contains "$(cat "$tmp/no-nvim-cache/wal/colors-wal.vim" 2>/dev/null || true)" \
    'let color15 = "#dee3e5"' "nvim renders its fallback cache even without nvim installed"

test_summary theming
