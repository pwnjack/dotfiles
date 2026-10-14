#!/bin/bash
# spicetify/apply_wal_colors.sh against a throwaway home, config and cache,
# with spicetify stubbed: the colour scheme keeps text fixed and surfaces in
# the readable band whatever the palette, and `spicetify refresh` runs only
# when it is safe (Pywal selected, client unpacked, no patch in progress). The
# fallback render is covered for every component by test/test-theming.sh.
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

home="$tmp/home" config="$tmp/config" cache="$tmp/cache" state="$tmp/state"
mkdir -p "$home" "$config/spicetify" "$config/scripts/theming" "$cache/wal" "$tmp/bin"
ln -s "$repo/scripts/theming/palette.sh" "$config/scripts/theming/palette.sh"
out="$cache/wal/spicetify-color.ini"
calls="$tmp/spicetify-calls"
printf '#!/bin/sh\necho "$@" >> "%s"\n' "$calls" > "$tmp/bin/spicetify"
chmod +x "$tmp/bin/spicetify"

palette() { for c in "$@"; do echo "#$c"; done > "$cache/wal/colors"; }
value() { sed -n "s/^$1[[:space:]]*=[[:space:]]*//p" "$out"; }
run() {
    HOME="$home" XDG_CONFIG_HOME="$config" XDG_CACHE_HOME="$cache" XDG_STATE_HOME="$state" \
        PATH="$tmp/bin:$PATH" bash "$repo/spicetify/apply_wal_colors.sh"
}

# A white palette must not give light surfaces, nor move the text colours.
palette ffffff ffffff ffffff ffffff ffffff ffffff ffffff ffffff \
        ffffff ffffff ffffff ffffff ffffff ffffff ffffff ffffff
run
check "renders without spicetify set up"
[ "$(value main)" = 242424 ] && [ "$(value sidebar)" = 1b1b1b ]
check "a white colour0 is clamped to the dark surface band"
[ "$(value text)" = ffffff ] && [ "$(value subtext)" = b3b3b3 ]
check "text stays Spotify's white and grey"
[ "$(sed -n '/=/p' "$out" | grep -cvE '^[a-z-]+ += [0-9a-f]{6}$')" -eq 0 ]
check "every value is bare six-digit hex, as color.ini requires"
[ "$(grep -c '^\[pywal\]$' "$out")" -eq 1 ]
check "the scheme is the [pywal] section the setup selects"

# A near-black palette still layers, and the accent follows primary.
printf 'primary=#0000aa\n' > "$cache/wal/roles"
palette 05090c 2a7789 4d7d85 318a9b 6097a1 8dafb4 9abbc2 cfddde \
        909a9b 2a7789 4d7d85 318a9b 6097a1 8dafb4 9abbc2 cfddde
run
[ "$(value main)" = 14191d ] && [ "$(value sidebar)" = 0b1013 ]
check "a near-black colour0 is lifted to the band, with the sidebar a step below"
[ "$(value button)" = 5481e6 ]
check "the accent follows primary with its OKLCH clamp"
[ ! -e "$calls" ]
check "nothing is refreshed without a spicetify config"

# Refresh only for the Pywal theme on an unpacked client, outside a patch run.
client="$tmp/client"
mkdir -p "$client/Apps/xpui"
ini() {
    printf '[Setting]\ncurrent_theme          = %s\nspotify_path           = %s\n' \
        "$1" "$client" > "$config/spicetify/config-xpui.ini"
}
ini Tokyo
run
[ ! -e "$calls" ]
check "another selected theme is left alone"

ini Pywal
run
grep -qx -- '-q -n refresh' "$calls"
check "the Pywal theme on an unpacked client is refreshed without a restart"

rm -f "$calls"
touch "$client/Apps/xpui.spa"
run
[ ! -e "$calls" ]
check "a packed client (SpotX not yet applied) is not refreshed"
rm "$client/Apps/xpui.spa"

mkdir -p "$state/spotify"
exec 8>"$state/spotify/patch.lock"
flock 8
# Not inherited: a waiter holding this descriptor would wait on itself.
run 8>&-
sleep 0.5
[ ! -e "$calls" ]
check "no refresh while the launcher holds the patch lock"
exec 8>&-
# The detached waiter refreshes once the patch run lets go.
for _ in $(seq 50); do [ -e "$calls" ] && break; sleep 0.1; done
grep -qx -- '-q -n refresh' "$calls" 2>/dev/null
check "a refresh queued behind the patch lock runs when it is released"

# The tracked symlink must name the file the script writes.
[ "$(basename "$(readlink "$repo/spicetify/Themes/Pywal/color.ini")")" = spicetify-color.ini ]
check "the tracked color.ini points at the rendered file"

echo "test-theme: $checks checks, $failed failed"
[ "$failed" -eq 0 ]
