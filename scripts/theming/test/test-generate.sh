#!/bin/bash
# Verify matugen generation, option validation and preservation on failure.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=scripts/lib/assert.sh
. "$ROOT/scripts/lib/assert.sh"
generator="$ROOT/scripts/theming/generate-palette.sh"
real_matugen=$(command -v matugen || true)
real_magick=$(command -v magick || true)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" XDG_CACHE_HOME="$tmp/cache"
export XDG_STATE_HOME="$tmp/state" XDG_DATA_HOME="$tmp/data"
export MATUGEN_ARGS="$tmp/args" MATUGEN_CWD="$tmp/cwd"
export MATUGEN_FIXTURE="$ROOT/scripts/theming/test/fixtures/matugen.json"
REAL_MV=$(command -v mv)
export REAL_MV
mkdir -p "$HOME" "$XDG_CONFIG_HOME/matugen" "$XDG_CONFIG_HOME/options" \
    "$XDG_CONFIG_HOME/scripts/theming" "$tmp/bin" "$tmp/no-matugen"
cp "$ROOT/matugen/config.toml" "$XDG_CONFIG_HOME/matugen/config.toml"
ln -s "$ROOT/scripts/theming/matugen-to-wal.sh" "$XDG_CONFIG_HOME/scripts/theming/matugen-to-wal.sh"
printf 'stub image\n' > "$tmp/image with spaces.png"
cat > "$tmp/bin/matugen" <<'STUB'
#!/bin/bash
call=1
while [ -e "$MATUGEN_ARGS.$call" ]; do call=$((call + 1)); done
printf '%s\n' "$@" > "$MATUGEN_ARGS.$call"
printf '%s\n' "$@" >> "$MATUGEN_ARGS"
if [ "${FAIL_SECOND_MATUGEN:-0}" = 1 ] && [ "$call" -eq 2 ]; then
    echo 'stub: ANSI generation failed' >&2
    exit 1
fi
pwd > "$MATUGEN_CWD"
if [ "${SLOW_MATUGEN:-0}" = 1 ]; then
    sleep 2
fi
if [ "${FAIL_MATUGEN:-0}" = 1 ]; then
    echo 'stub: corrupt image' >&2
    exit 1
fi
if [ "${BAD_JSON:-0}" = 1 ]; then
    printf 'invalid json\n'
else
    cat "$MATUGEN_FIXTURE"
fi
STUB
chmod +x "$tmp/bin/matugen"
cat > "$tmp/bin/mv" <<'STUB'
#!/bin/bash
if [ "${FAIL_PUBLISH:-0}" = 1 ] && [[ "$3" == */.generate.*/colors ]]; then
    echo 'stub: colors rename failed' >&2
    exit 1
fi
if [ -n "${PUBLISH_LOG:-}" ] && [[ "$3" == */.generate.*/roles || "$3" == */.generate.*/colors ]]; then
    printf '%s\n' "${3##*/}" >> "$PUBLISH_LOG"
fi
exec "$REAL_MV" "$@"
STUB
chmod +x "$tmp/bin/mv"
export PATH="$tmp/bin:$PATH"

run_generate() {
    rm -f "$MATUGEN_ARGS" "$MATUGEN_ARGS".[0-9]*
    bash "$generator" "$@" > "$tmp/stdout" 2> "$tmp/stderr"
    rc=$?
}
kept_palette() {
    if cmp -s "$tmp/colors.before" "$XDG_CACHE_HOME/wal/colors" && \
       cmp -s "$tmp/roles.before" "$XDG_CACHE_HOME/wal/roles"; then
        pass "$1"
    else
        fail "$1"
    fi
}
run_generate "$tmp/image with spaces.png"
assert_eq "$rc" 0 'missing option files use defaults'
assert_eq "$(grep -cx image "$MATUGEN_ARGS")" 1 'default options use exactly one matugen pass'
if [ ! -f "$XDG_CACHE_HOME/wal/colors" ] || [ ! -f "$XDG_CACHE_HOME/wal/roles" ]; then
    fail 'both palette files are written' "$(cat "$tmp/stderr")"
    test_summary generate
    exit 1
fi
pass 'both palette files are written'
args=$(cat "$MATUGEN_ARGS")
assert_contains "$args" $'-t\nscheme-tonal-spot\n--contrast\n0\n--prefer\nsaturation' 'default generator options'
assert_contains "$args" $'--dry-run\n--json\nhex\n-q' 'matugen renders no templates'
assert_contains "$args" $'--fallback-color\n#6097a1' 'fallback seed is explicit'
assert_contains "$args" $'-c\n'"$XDG_CONFIG_HOME/matugen/config.toml"$'\n-m\ndark' 'config path and dark mode'
assert_contains "$args" $'image\n'"$tmp/image with spaces.png" 'image path remains one argument'
scratch=$(cat "$MATUGEN_CWD")
if [ "$scratch" != "$PWD" ] && [ ! -e "$scratch" ]; then
    pass 'matugen runs in a scratch directory which is cleaned up'
else
    fail 'matugen scratch directory isolation and cleanup'
fi
assert_eq "$(cat "$tmp/stderr")" '' 'defaults produce no warnings'

printf 'scheme-vibrant\n' > "$XDG_CONFIG_HOME/options/theme-scheme"
printf '0.5\n' > "$XDG_CONFIG_HOME/options/theme-contrast"
printf 'darkness\n' > "$XDG_CONFIG_HOME/options/theme-prefer"
run_generate "$tmp/image with spaces.png"
assert_eq "$rc" 0 'valid option files succeed'
assert_contains "$(cat "$MATUGEN_ARGS")" $'-t\nscheme-vibrant\n--contrast\n0.5\n--prefer\ndarkness' 'valid options reach matugen'
printf ' \tscheme-vibrant \r\n' > "$XDG_CONFIG_HOME/options/theme-scheme"
printf ' \t-1.00 \r\n' > "$XDG_CONFIG_HOME/options/theme-contrast"
printf '\tclosest-to-fallback \r\n' > "$XDG_CONFIG_HOME/options/theme-prefer"
run_generate "$tmp/image with spaces.png"
assert_eq "$rc" 0 'surrounding whitespace and CRLF are accepted'
assert_contains "$(cat "$MATUGEN_ARGS")" $'-t\nscheme-vibrant\n--contrast\n-1.00\n--prefer\nclosest-to-fallback' 'trimmed values reach matugen'
assert_eq "$(cat "$tmp/stderr")" '' 'valid trimmed options produce no warnings'

# Either a scheme or contrast change needs a fixed ANSI pass with the same source.
for variant in scheme contrast; do
    printf 'scheme-tonal-spot\n' > "$XDG_CONFIG_HOME/options/theme-scheme"
    printf '0\n' > "$XDG_CONFIG_HOME/options/theme-contrast"
    printf 'lightness\n' > "$XDG_CONFIG_HOME/options/theme-prefer"
    if [ "$variant" = scheme ]; then
        printf 'scheme-vibrant\n' > "$XDG_CONFIG_HOME/options/theme-scheme"
    else
        printf '0.5\n' > "$XDG_CONFIG_HOME/options/theme-contrast"
    fi
    expected_scheme=$(cat "$XDG_CONFIG_HOME/options/theme-scheme")
    expected_contrast=$(cat "$XDG_CONFIG_HOME/options/theme-contrast")
    run_generate "$tmp/image with spaces.png"
    assert_eq "$rc" 0 "$variant change succeeds"
    assert_contains "$(cat "$MATUGEN_ARGS.1")" $'-t\n'"$expected_scheme"$'\n--contrast\n'"$expected_contrast"$'\n--prefer\nlightness' "$variant first pass uses chosen scheme/contrast and prefer"
    assert_eq "$(grep -cx image "$MATUGEN_ARGS")" 2 "$variant change uses exactly two matugen passes"
    assert_contains "$(cat "$MATUGEN_ARGS.2")" $'-t\nscheme-tonal-spot\n--contrast\n0\n--prefer\nlightness' "$variant ANSI pass uses fixed scheme/contrast and chosen prefer"
    for part in $'image\n'"$tmp/image with spaces.png" $'--fallback-color\n#6097a1' $'--dry-run\n--json\nhex\n-q'; do
        assert_contains "$(cat "$MATUGEN_ARGS.2")" "$part" "$variant ANSI pass keeps image, fallback and output flags"
    done
done
cp "$XDG_CACHE_HOME/wal/colors" "$tmp/colors.before"
cp "$XDG_CACHE_HOME/wal/roles" "$tmp/roles.before"
export FAIL_SECOND_MATUGEN=1
run_generate "$tmp/image with spaces.png"
assert_eq "$rc" 1 'failed second matugen pass exits 1'
assert_contains "$(cat "$tmp/stderr")" 'ANSI generation failed' 'second-pass failure names its cause'
kept_palette 'failed second matugen pass preserves both palette files byte for byte'
unset FAIL_SECOND_MATUGEN

printf 'bogus\n' > "$XDG_CONFIG_HOME/options/theme-scheme"
printf '7\n' > "$XDG_CONFIG_HOME/options/theme-contrast"
printf 'bogus\n' > "$XDG_CONFIG_HOME/options/theme-prefer"
run_generate "$tmp/image with spaces.png"
assert_eq "$rc" 0 'invalid options fall back successfully'
assert_contains "$(cat "$MATUGEN_ARGS")" $'-t\nscheme-tonal-spot\n--contrast\n0\n--prefer\nsaturation' 'invalid options use defaults'
for name in theme-scheme theme-contrast theme-prefer; do
    assert_contains "$(cat "$tmp/stderr")" "options/$name" "warning names $name"
done
printf 'scheme-vi\rbrant\n' > "$XDG_CONFIG_HOME/options/theme-scheme"
printf '1.01\n' > "$XDG_CONFIG_HOME/options/theme-contrast"
printf '\t \r\n' > "$XDG_CONFIG_HOME/options/theme-prefer"
run_generate "$tmp/image with spaces.png"
assert_eq "$rc" 0 'internal CR, out-of-range decimal and empty value fall back'
assert_contains "$(cat "$MATUGEN_ARGS")" $'-t\nscheme-tonal-spot\n--contrast\n0\n--prefer\nsaturation' 'only surrounding whitespace is trimmed'
rm "$XDG_CONFIG_HOME/options/"theme-*
cp "$XDG_CACHE_HOME/wal/colors" "$tmp/colors.before"
cp "$XDG_CACHE_HOME/wal/roles" "$tmp/roles.before"

export FAIL_MATUGEN=1
run_generate "$tmp/image with spaces.png"
assert_eq "$rc" 1 'failed matugen exits 1'
assert_contains "$(cat "$tmp/stderr")" 'corrupt image' 'matugen failure names its cause'
kept_palette 'failed matugen preserves both palette files byte for byte'
unset FAIL_MATUGEN
export SLOW_MATUGEN=1 GENERATE_TIMEOUT=0.1
run_generate "$tmp/image with spaces.png"
assert_eq "$rc" 1 'timed-out matugen exits 1'
assert_contains "$(cat "$tmp/stderr")" 'matugen failed' 'matugen timeout is identified as generation failure'
kept_palette 'timed-out matugen preserves both palette files byte for byte'
unset SLOW_MATUGEN GENERATE_TIMEOUT
export BAD_JSON=1
run_generate "$tmp/image with spaces.png"
assert_eq "$rc" 1 'invalid matugen JSON exits 1'
assert_contains "$(cat "$tmp/stderr")" 'conversion' 'conversion failure is identified'
kept_palette 'conversion failure preserves both palette files byte for byte'
unset BAD_JSON

# Restrict PATH to the generator/converter's tools, excluding host matugen.
for tool in bash jq mktemp cat rm mv cp chmod mkdir tr wc grep sed dirname; do
    if [ "$tool" = mv ]; then
        ln -s "$REAL_MV" "$tmp/no-matugen/$tool"
    else
        ln -s "$(command -v "$tool")" "$tmp/no-matugen/$tool"
    fi
done
PATH="$tmp/no-matugen" run_generate "$tmp/image with spaces.png"
assert_eq "$rc" 1 'missing matugen exits 1'
assert_contains "$(cat "$tmp/stderr")" 'matugen is not installed' 'missing matugen is identified'
kept_palette 'missing matugen preserves both palette files byte for byte'

run_generate "$tmp/image with spaces.png" "$tmp/explicit output"
assert_eq "$rc" 0 'explicit output directory succeeds'
if cmp -s "$tmp/explicit output/colors" "$tmp/colors.before" && \
   cmp -s "$tmp/explicit output/roles" "$tmp/roles.before"; then
    pass 'explicit output receives both palette files'
else
    fail 'explicit output receives both palette files'
fi
kept_palette 'explicit output leaves the default cache untouched'

# A standalone publication must wait for wall.sh's lock, even when the
# default cache is passed explicitly. Renames are logged by the mv stub.
export PUBLISH_LOG="$tmp/publication-order"
(
    exec 8>"$XDG_CACHE_HOME/wal/wallpaper.lock"
    flock 8
    touch "$tmp/lock-held"
    sleep 0.5
    printf 'released\n' >> "$PUBLISH_LOG"
) &
lock_pid=$!
while [ ! -e "$tmp/lock-held" ]; do sleep 0.01; done
run_generate "$tmp/image with spaces.png" "$XDG_CACHE_HOME/wal"
assert_eq "$rc" 0 'default-cache publication succeeds after the lock is released'
wait "$lock_pid"
assert_eq "$(cat "$PUBLISH_LOG")" $'released\nroles\ncolors' \
    'default-cache publication waits for the lock and renames roles before colors'
unset PUBLISH_LOG

# wall.sh already owns the default lock while generating into next/.
(
    exec 8>"$XDG_CACHE_HOME/wal/wallpaper.lock"
    flock 8
    timeout 2 bash "$generator" "$tmp/image with spaces.png" "$XDG_CACHE_HOME/wal/next"
) > "$tmp/stdout" 2> "$tmp/stderr"
assert_eq "$?" 0 'explicit staging output does not acquire the held default lock'
mkdir -p "$tmp/blocked/roles"
cp "$tmp/colors.before" "$tmp/blocked/colors"
run_generate "$tmp/image with spaces.png" "$tmp/blocked"
assert_eq "$rc" 1 'non-file palette destination is rejected'
if cmp -s "$tmp/blocked/colors" "$tmp/colors.before" && [ -d "$tmp/blocked/roles" ]; then
    pass 'publication failure leaves existing destinations untouched'
else
    fail 'publication failure leaves existing destinations untouched'
fi

mkdir -p "$tmp/rollback"
printf 'previous colors\n' > "$tmp/rollback/colors"
printf 'previous roles\n' > "$tmp/rollback/roles"
export FAIL_PUBLISH=1
run_generate "$tmp/image with spaces.png" "$tmp/rollback"
assert_eq "$rc" 1 'second rename failure exits 1'
assert_eq "$(cat "$tmp/rollback/colors")" 'previous colors' 'second rename failure keeps previous colors'
assert_eq "$(cat "$tmp/rollback/roles")" 'previous roles' 'second rename failure restores previous roles'
run_generate "$tmp/image with spaces.png" "$tmp/rollback-empty"
assert_eq "$rc" 1 'second rename failure without a previous palette exits 1'
if [ ! -e "$tmp/rollback-empty/colors" ] && [ ! -e "$tmp/rollback-empty/roles" ]; then
    pass 'second rename failure removes unpublished new files'
else
    fail 'second rename failure removes unpublished new files'
fi
unset FAIL_PUBLISH
(cd "$tmp" && bash "$generator" 'image with spaces.png' 'relative output') > "$tmp/stdout" 2> "$tmp/stderr"
assert_eq "$?" 0 'relative image and output paths succeed from a scratch cwd'
if cmp -s "$tmp/relative output/colors" "$tmp/colors.before" && \
   cmp -s "$tmp/relative output/roles" "$tmp/roles.before"; then
    pass 'relative output receives both palette files'
else
    fail 'relative output receives both palette files'
fi

if [ -n "$real_matugen" ] && [ -n "$real_magick" ]; then
    ln -sf "$real_matugen" "$tmp/bin/matugen"
    "$real_magick" -size 64x64 xc:'#808080' "$tmp/grey.png"
    run_generate "$tmp/grey.png"
    assert_eq "$rc" 0 'real matugen generates a grey wallpaper palette'
    if [ "$rc" -eq 0 ]; then
        # shellcheck source=scripts/theming/palette.sh
        . "$ROOT/scripts/theming/palette.sh"
        # shellcheck disable=SC2034 # Filled by role_load, read by wal_role.
        declare -A role=()
        role_load
        assert_eq "$(wal_role primary)" '#82d3e1' 'grey wallpaper uses the fallback seed rather than Material blue'
    else
        fail 'grey wallpaper fallback' "$(cat "$tmp/stderr")"
    fi
else
    echo '  skip: real grey wallpaper fallback (needs matugen and magick)'
fi
test_summary generate
