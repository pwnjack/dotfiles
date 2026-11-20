#!/bin/bash
#
# The wallpaper discovery that sddm/update_sddm_root.sh runs as the user (the
# single-quoted `bash -c` block handed to runuser), exercised on its own
# against a fake home. It cannot share scripts/lib/wallpaper.sh, so this pins
# the same choices: awww 0.12's NUL-separated cache, the monitor preference,
# ignoring non-path cache files, the current-wallpaper fallback, and success
# with no wallpaper at all.
#

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/assert.sh
. "$ROOT/scripts/lib/assert.sh"

block=$(python3 - "$ROOT/sddm/update_sddm_root.sh" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
match = re.search(r"/bin/bash -c '\n(.*?)\n' _ \"\$USER_HOME\"", text, re.S)
print(match.group(1) if match else '')
PY
)
if [ -z "$block" ]; then
    fail "could not find the discovery block in sddm/update_sddm_root.sh"
    test_summary
    exit
fi
discover() { bash -c "$block" _ "$home"; }

home=$(mktemp -d)
trap 'rm -rf "$home"' EXIT
cache="$home/.cache/awww/0.12.1"
mkdir -p "$home/.config/options" "$cache" "$home/walls"
a="$home/walls/a b.jpg" b="$home/walls/b.jpg"
touch "$a" "$b"
printf '\0crop:center\0Lanczos3\0%s' "$a" > "$cache/FIXTURE-A"
touch -d '1 minute ago' "$cache/FIXTURE-A"
printf '\0crop:center\0Lanczos3\0%s' "$b" > "$cache/FIXTURE-B"
touch -d '2 minutes ago' "$cache/FIXTURE-B"
printf '\x01/\xff garbage\n/x\0junk' > "$cache/animation-frames"

: > "$home/.config/options/mainmonitor"
assert_eq "$(discover)" "$a" \
    "no preference: newest real entry wins over a newer non-path cache file"
echo FIXTURE-B > "$home/.config/options/mainmonitor"
assert_eq "$(discover)" "$b" "the preferred monitor's entry wins"
rm "$b"
ln -s "$a" "$home/.config/options/wallpaper"
assert_eq "$(discover)" "$a" \
    "an entry naming a deleted image falls back to the current-wallpaper link"
rm "$home/.config/options/wallpaper" "$cache"/*
assert_eq "$(discover; echo "status=$?")" "status=0" \
    "no wallpaper anywhere: empty output and success"
assert_eq "$(grep -c "'" <<< "$block")" "0" \
    "the block contains no single quote (it is itself single-quoted)"

test_summary
