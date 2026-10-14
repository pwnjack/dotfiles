#!/bin/bash
# Verify matugen JSON conversion and preservation of a working palette.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=scripts/lib/assert.sh
. "$ROOT/scripts/lib/assert.sh"
fixture="$ROOT/scripts/theming/test/fixtures/matugen.json"
converter="$ROOT/scripts/theming/matugen-to-wal.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

c() {
    jq -r --arg name "$1" '.colors[$name].dark.color' "$fixture" | tr A-F a-f
}

if ! bash "$converter" "$fixture" "$tmp/out" >"$tmp/stdout" 2>"$tmp/stderr"; then
    fail 'converter accepts the real matugen fixture' "$(cat "$tmp/stderr")"
    test_summary convert
    exit 1
fi
pass 'converter accepts the real matugen fixture'
mapfile -t colors < "$tmp/out/colors"
assert_eq "${#colors[@]}" 16 'colors has exactly 16 lines'
if grep -qEv '^#[0-9a-f]{6}$' "$tmp/out/colors"; then
    fail 'all colors are lowercase hex'
else
    pass 'all colors are lowercase hex'
fi
slots=(surface red green yellow blue magenta cyan on_surface outline
       on_red_container on_green_container on_yellow_container
       on_blue_container on_magenta_container on_cyan_container on_surface)
for i in "${!slots[@]}"; do
    assert_eq "${colors[$i]:-}" "$(c "${slots[$i]}")" "slot $i = ${slots[$i]}"
done
roles=(surface surface_container_low surface_container surface_container_high
       surface_container_highest on_surface on_surface_variant outline outline_variant
       primary on_primary primary_container on_primary_container secondary_container
       on_secondary_container tertiary_container on_tertiary_container error on_error)
for role in "${roles[@]}"; do
    assert_contains "$(cat "$tmp/out/roles")" "$role=$(c "$role")" "role $role"
done
for tone in 30 40 50 60 70 80 90 95; do
    expected=$(jq -r --arg tone "$tone" '.palettes.primary[$tone].color | ascii_downcase' "$fixture")
    assert_contains "$(cat "$tmp/out/roles")" "primary_t$tone=$expected" "primary tone $tone"
done
assert_eq "$(wc -l < "$tmp/out/roles")" 27 'roles has exactly 27 lines'
if grep -qEv '^[a-z0-9_]+=#[0-9a-f]{6}$' "$tmp/out/roles"; then
    fail 'all roles are named lowercase hex'
else
    pass 'all roles are named lowercase hex'
fi
assert_eq "$(stat -c %a "$tmp/out/colors")" 644 'colors permissions'
assert_eq "$(stat -c %a "$tmp/out/roles")" 644 'roles permissions'
cp "$tmp/out/colors" "$tmp/colors.before"
cp "$tmp/out/roles" "$tmp/roles.before"
jq 'del(.colors.red)' "$fixture" > "$tmp/missing.json"
printf 'not json\n' > "$tmp/invalid.json"
jq 'del(.palettes.primary["95"])' "$fixture" > "$tmp/missing-tone.json"
jq '.colors.surface.dark.color = "#xyzxyz"' "$fixture" > "$tmp/invalid-hex.json"
for bad in missing invalid missing-tone invalid-hex; do
    if bash "$converter" "$tmp/$bad.json" "$tmp/out" >"$tmp/stdout" 2>"$tmp/stderr"; then
        fail "$bad input is rejected"
    else
        assert_eq "$?" 1 "$bad input exits 1"
    fi
    if cmp -s "$tmp/colors.before" "$tmp/out/colors" && cmp -s "$tmp/roles.before" "$tmp/out/roles"; then
        pass "$bad input preserves both files"
    else
        fail "$bad input changed the working palette"
    fi
done
# Only chromatic slots may come from the independent terminal palette.
jq '.colors.red.dark.color = "#123456" | .colors.on_red_container.dark.color = "#abcdef"
    | .colors.surface.dark.color = "#010101" | .colors.on_surface.dark.color = "#020202"
    | .colors.outline.dark.color = "#030303" | .colors.primary.dark.color = "#040404"' \
    "$fixture" > "$tmp/ansi.json"
bash "$converter" "$fixture" "$tmp/out" "$tmp/ansi.json"
assert_eq "$?" 0 'converter accepts separate ANSI JSON'
mapfile -t colors < "$tmp/out/colors"
assert_eq "${colors[1]}" '#123456' 'slot 1 uses ANSI red'
assert_eq "${colors[9]}" '#abcdef' 'slot 9 uses ANSI on_red_container'
for i in 0 7 8 15; do
    assert_eq "${colors[$i]}" "$(c "${slots[$i]}")" "slot $i retains the main palette"
done
if cmp -s "$tmp/roles.before" "$tmp/out/roles"; then
    pass 'all roles retain the main palette'
else
    fail 'separate ANSI JSON changed roles'
fi
cp "$tmp/out/colors" "$tmp/colors.before"
for bad in missing invalid invalid-hex; do
    # invalid-hex must affect a consumed ANSI slot, not an ignored surface.
    if [ "$bad" = invalid-hex ]; then
        jq '.colors.red.dark.color = "#xyzxyz"' "$fixture" > "$tmp/$bad.json"
    fi
    if bash "$converter" "$fixture" "$tmp/out" "$tmp/$bad.json" >"$tmp/stdout" 2>"$tmp/stderr"; then
        fail "$bad ANSI JSON is rejected"
    else
        assert_eq "$?" 1 "$bad ANSI JSON exits 1"
    fi
    if cmp -s "$tmp/colors.before" "$tmp/out/colors" && cmp -s "$tmp/roles.before" "$tmp/out/roles"; then
        pass "$bad ANSI JSON preserves both files"
    else
        fail "$bad ANSI JSON changed the working palette"
    fi
done
assert_eq "$(find "$tmp/out" -type f | wc -l)" 2 'temporary files are cleaned up'
test_summary convert
