#!/bin/bash
# zen/apply_wal_colors.sh against a throwaway home, config and cache: the CSS
# follows the palette, and the script wires up only the profile Zen launches,
# once, without touching a userChrome.css of the user's own. The fallback
# render and leftover tokens are covered for every component by
# test/test-theming.sh.
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

home="$tmp/home" config="$tmp/config" cache="$tmp/cache"
mkdir -p "$home" "$config/zen" "$config/scripts/theming" "$cache/wal"
ln -s "$repo/zen/userChrome.css.in" "$config/zen/userChrome.css.in"
ln -s "$repo/scripts/theming/palette.sh" "$config/scripts/theming/palette.sh"
out="$cache/wal/zen-userChrome.css"
for c in 101010 aa0000 00aa00 aaaa00 0000bb aa00aa 00aaaa aaaaaa \
         555555 ff5555 55ff55 ffff55 5555ff ff55ff 55ffff ffffff; do
    echo "#$c"
done > "$cache/wal/colors"
printf 'primary=#0000aa\n' > "$cache/wal/roles"

run() { HOME="$home" XDG_CONFIG_HOME="$config" XDG_CACHE_HOME="$cache" bash "$repo/zen/apply_wal_colors.sh"; }

# No Zen: the theme still renders and nothing is created under ~/.zen.
run
check "renders without Zen installed"
grep -q "from #101010 " "$out"
check "the base follows colour0"
grep -q "from #0000aa " "$out"
check "the accent follows primary"
[ ! -e "$home/.zen" ]
check "no ~/.zen appears when Zen is not installed"

# Two profiles: Default=1 marks one, but the install launches the other.
launched="$home/.zen/abcd.Default (release)" other="$home/.zen/efgh.Default Profile"
mkdir -p "$launched" "$other"
cat > "$home/.zen/profiles.ini" <<'INI'
[Profile1]
Name=Default Profile
IsRelative=1
Path=efgh.Default Profile
Default=1

[Profile0]
Name=Default (release)
IsRelative=1
Path=abcd.Default (release)

[General]
StartWithLastProfile=1

[Install0123456789ABCDEF]
Default=abcd.Default (release)
Locked=1
INI
echo 'user_pref("browser.startup.page", 3);' > "$launched/user.js"

run
check "runs with Zen installed"
[ "$(readlink "$launched/chrome/userChrome.css")" = "$out" ]
check "the launched profile's userChrome.css links to the rendered file"
grep -qxF 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' "$launched/user.js"
check "user.js turns on userChrome.css loading"
grep -qxF 'user_pref("browser.startup.page", 3);' "$launched/user.js"
check "existing user.js lines are kept"
[ ! -e "$other/chrome" ] && [ ! -e "$other/user.js" ]
check "the profile Zen does not launch is left alone"

first=$(cat "$out")
run
[ "$(cat "$out")" = "$first" ]
check "a second run renders the same CSS"
[ "$(grep -c legacyUserProfileCustomizations "$launched/user.js")" -eq 1 ]
check "a second run does not add the pref again"

# A user.js whose last line has no newline gets the pref on a line of its own.
printf 'user_pref("browser.startup.page", 3);' > "$launched/user.js"
run && run
[ "$(grep -c legacyUserProfileCustomizations "$launched/user.js")" -eq 1 ] &&
    grep -qxF 'user_pref("browser.startup.page", 3);' "$launched/user.js"
check "a user.js without a final newline gets the pref once, on its own line"

# A link left by an earlier cache location is ours and is re-pointed.
ln -sfn "$tmp/old-cache/wal/zen-userChrome.css" "$launched/chrome/userChrome.css"
run
[ "$(readlink "$launched/chrome/userChrome.css")" = "$out" ]
check "a stale link to an earlier zen-userChrome.css is re-pointed"

# profiles.ini saved with CRLF line endings still resolves the profile.
rm "$launched/chrome/userChrome.css"
sed -i 's/$/\r/' "$home/.zen/profiles.ini"
run
[ "$(readlink "$launched/chrome/userChrome.css")" = "$out" ]
check "a CRLF profiles.ini still finds the launched profile"

# A userChrome.css of the user's own is never replaced.
rm "$launched/chrome/userChrome.css"
echo '/* mine */' > "$launched/chrome/userChrome.css"
run 2>/dev/null
check "a foreign userChrome.css is not an error"
[ ! -L "$launched/chrome/userChrome.css" ] && grep -q mine "$launched/chrome/userChrome.css"
check "a foreign userChrome.css is left untouched"

echo "test-theme: $checks checks, $failed failed"
[ "$failed" -eq 0 ]
