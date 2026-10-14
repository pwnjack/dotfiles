#!/bin/bash
#
# Shared matugen palette and semantic-role loader, sourced by each component.
# wal_load() fills the caller's `wal` array with 16 hex colors in the fixed
# slot order; role_load() fills the caller's `declare -A role=()` with all
# fixed roles and primary tones. wal_role <name> returns a loaded role.
#
# Read ~/.cache/wal/colors (16 plain hex lines) and roles (name=#rrggbb),
# never evaluating generated files as shell. Slots and roles fall back
# independently until matugen first runs, including a slots-only older cache.
# Every apply script must produce output on a fresh checkout: the repo tracks
# symlinks to those outputs, and a dangling tracked symlink is a doctor ERROR.
#

# Built-in palette, used only until the first generation: matugen's dark
# scheme for #6097a1 in the fixed slot order (see matugen-to-wal.sh).
_WAL_FALLBACK=(
    '#0e1416' '#ffb2bd' '#91d5ac' '#e0c56d'
    '#98ccf9' '#c7bfff' '#81d3de' '#dee3e5'
    '#899294' '#ffd9dd' '#adf2c7' '#fde186'
    '#cbe6ff' '#e4dfff' '#9df0fb' '#dee3e5'
)
_ROLE_FALLBACK=(
    surface=#0e1416 surface_container_low=#171d1e surface_container=#1b2122
    surface_container_high=#252b2c surface_container_highest=#303637
    on_surface=#dee3e5 on_surface_variant=#bfc8ca outline=#899294 outline_variant=#3f484a
    primary=#82d3e1 on_primary=#00363d primary_container=#004f58 on_primary_container=#9eeffe
    secondary_container=#334b4f on_secondary_container=#cde7ec
    tertiary_container=#3b4665 on_tertiary_container=#dae2ff error=#ffb4ab on_error=#690005
    primary_t30=#004f58 primary_t40=#006875 primary_t50=#008393 primary_t60=#009fb2
    primary_t70=#24bcd0 primary_t80=#50d8ec primary_t90=#9bf0ff primary_t95=#d1f7ff
)

# Fills `wal` in the caller's scope. Callers declare it first so that the
# variable is visibly assigned at the call site.
# shellcheck disable=SC2034  # `wal` is the output, read by the sourcing script.
wal_load() {
    local colors_file="${XDG_CACHE_HOME:-$HOME/.cache}/wal/colors"
    local -a loaded=()
    local line

    if [ -r "$colors_file" ]; then
        while IFS= read -r line; do
            # Tolerate stray blank lines. Anything that is not a hex triplet
            # means the file is not what we expect: stop reading, so the count
            # below falls short of 16 and the fallback is used. Returning here
            # instead would leave `wal` unset and break the contract that this
            # function always yields a usable palette.
            [ -n "$line" ] || continue
            [[ "$line" == \#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F] ]] || break
            loaded+=("$line")
        done < "$colors_file"
    fi

    if [ "${#loaded[@]}" -eq 16 ]; then
        wal=("${loaded[@]}")
    else
        wal=("${_WAL_FALLBACK[@]}")
    fi
}

# Fills the caller's associative `role` array with every fixed name, then
# overrides only known roles with valid lowercase hex from the cache.
role_load() {
    local roles_file="${XDG_CACHE_HOME:-$HOME/.cache}/wal/roles"
    local entry name value

    role=()
    for entry in "${_ROLE_FALLBACK[@]}"; do
        role[${entry%%=*}]=${entry#*=}
    done
    if [ -r "$roles_file" ]; then
        while IFS='=' read -r name value || [ -n "$name" ]; do
            [ -n "$name" ] || continue
            if [[ ${role[$name]+present} && "$value" =~ ^#[0-9a-f]{6}$ ]]; then
                role[$name]=$value
            fi
        done < "$roles_file"
    fi
}

wal_role() {
    printf '%s' "${role[$1]}"
}

# Echoes whichever of wal[0] / wal[15] stays legible as text on the given
# background color.
#
# A wallpaper palette is not designed for contrast: color1 can come out nearly
# black on one image and near-white on the next, so any fixed text color is
# unreadable half the time. This picks per background instead.
#
# The threshold is ITU-R BT.601 perceived brightness, the same weighting most
# terminal themes use. It is integer math on purpose — bash has no floats and
# pulling in bc for a light/dark decision is not worth it.
wal_readable_on() {
    local hex="${1#\#}"
    local r g b brightness

    r=$((16#${hex:0:2}))
    g=$((16#${hex:2:2}))
    b=$((16#${hex:4:2}))
    brightness=$(( (299 * r + 587 * g + 114 * b) / 1000 ))

    if [ "$brightness" -gt 128 ]; then
        printf '%s' "${wal[0]}"
    else
        printf '%s' "${wal[15]}"
    fi
}

# wal_render <template> <output>
#
# Copies a template with every @colorN@ replaced by wal[N] and every
# @oncolorN@ by the text color readable on it. Call wal_load first.
# When `role` is declared, replace @role_<name>@ too; call role_load first.
#
# Highest index first: @color1@ is a prefix of @color15@, so substituting it
# first would leave a stray "5" behind.
wal_render() {
    local -a sed_args=()
    local i
    for ((i = 15; i >= 0; i--)); do
        sed_args+=(-e "s|@color$i@|${wal[$i]}|g")
        sed_args+=(-e "s|@oncolor$i@|$(wal_readable_on "${wal[$i]}")|g")
    done
    if declare -p role >/dev/null 2>&1; then
        local name
        for name in "${!role[@]}"; do
            sed_args+=(-e "s|@role_${name}@|${role[$name]}|g")
        done
    fi
    sed "${sed_args[@]}" "$1" > "$2"
}

# wal_oklch <hex> <lmin> <lmax> <cmax> [dl]
#
# Echoes <hex> with its OKLCH lightness clamped to [lmin, lmax], its chroma
# capped at cmax, and dl then added to the lightness; hue is kept. This is the
# CSS themes' `oklch(from X clamp(lmin, l, lmax) min(c, cmax) h)` for
# consumers that accept only hex, so every component can keep surfaces and
# accents in the same readable range whatever the wallpaper gives.
#
# awk because bash has no floats. A result outside sRGB is clipped per
# channel, which only happens for strong accents and shifts them slightly.
wal_oklch() {
    awk -v hex="${1#\#}" -v lmin="$2" -v lmax="$3" -v cmax="$4" -v dl="${5:-0}" '
        function byte(i) {
            return (index("0123456789abcdef", substr(hex, i, 1)) - 1) * 16 \
                 + index("0123456789abcdef", substr(hex, i + 1, 1)) - 1
        }
        function lin(c) { c /= 255; return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4 }
        function cbrt(x) { return x <= 0 ? 0 : exp(log(x) / 3) }
        function enc(c) {
            c = c <= 0.0031308 ? 12.92 * c : 1.055 * c ^ (1 / 2.4) - 0.055
            c = c < 0 ? 0 : (c > 1 ? 1 : c)
            return int(c * 255 + 0.5)
        }
        BEGIN {
            hex = tolower(hex)
            r = lin(byte(1)); g = lin(byte(3)); b = lin(byte(5))
            l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
            m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
            s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
            L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
            A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
            B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
            C = sqrt(A * A + B * B)
            if (C > cmax) { A *= cmax / C; B *= cmax / C }
            L = (L < lmin ? lmin : (L > lmax ? lmax : L)) + dl
            L = L < 0 ? 0 : (L > 1 ? 1 : L)
            l = (L + 0.3963377774 * A + 0.2158037573 * B) ^ 3
            m = (L - 0.1055613458 * A - 0.0638541728 * B) ^ 3
            s = (L - 0.0894841775 * A - 1.2914855480 * B) ^ 3
            printf "#%02x%02x%02x\n",
                enc( 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                enc(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                enc(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        }'
}
