#!/bin/bash
# vesktop/apply_wal_colors.sh against a throwaway config and cache: the theme
# follows the palette, is idempotent, and touches the themes-directory symlink
# that a running Vesktop watches. The fallback render and leftover tokens are
# covered for every component by test/test-theming.sh.
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd -- "$here/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

failed=0 checks=0
# Records the exit status of the command just before it.
check() {
    local rc=$?
    checks=$((checks + 1))
    if [ "$rc" -ne 0 ]; then
        failed=$((failed + 1))
        echo "FAIL: $1"
    fi
}

# The script reads its template, the palette loader and the symlink from
# XDG_CONFIG_HOME, so a fake config that links the real two files is enough.
config="$tmp/config" cache="$tmp/cache"
mkdir -p "$config/vesktop/themes" "$config/scripts/theming" "$cache"
ln -s "$repo/vesktop/pywal.theme.css.in" "$config/vesktop/pywal.theme.css.in"
ln -s "$repo/scripts/theming/palette.sh" "$config/scripts/theming/palette.sh"
ln -s "$cache/wal/vesktop.theme.css" "$config/vesktop/themes/pywal.theme.css"
out="$cache/wal/vesktop.theme.css"

run() { XDG_CONFIG_HOME="$config" XDG_CACHE_HOME="$cache" bash "$repo/vesktop/apply_wal_colors.sh"; }

mkdir -p "$cache/wal"
for c in 101010 aa0000 00aa00 aaaa00 0000bb aa00aa 00aaaa aaaaaa \
         555555 ff5555 55ff55 ffff55 5555ff ff55ff 55ffff ffffff; do
    echo "#$c"
done > "$cache/wal/colors"
printf 'primary=#0000aa\n' > "$cache/wal/roles"
touch -h -d '2000-01-01' "$config/vesktop/themes/pywal.theme.css"
run
check "renders with a matugen palette"
grep -q "from #101010 " "$out"
check "the base follows colour0"
grep -q "from #0000aa " "$out"
check "the accent follows primary"
[ "$(stat -c %Y "$config/vesktop/themes/pywal.theme.css")" -gt 946684800 ]
check "the themes-directory symlink is touched so Vesktop reloads"

first=$(cat "$out")
run
[ "$(cat "$out")" = "$first" ]
check "a second run renders the same theme"

# The tracked symlink must name the file the script writes.
[ "$(basename "$(readlink "$repo/vesktop/themes/pywal.theme.css")")" = vesktop.theme.css ]
check "the tracked symlink points at the rendered file"

echo "test-theme: $checks checks, $failed failed"
[ "$failed" -eq 0 ]
