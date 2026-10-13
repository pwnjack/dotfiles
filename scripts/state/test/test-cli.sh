#!/bin/bash
# overlay.sh and overlay-cli.mjs against throwaway trees; never the real state.
set -euo pipefail
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/assert.sh"

src="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A minimal config tree with the engine copied in, so overlay.sh resolves its
# config dir from its own location exactly as it does in ~/.config.
make_tree() {
    local root=$1
    mkdir -p "$root/scripts/state" "$root/defaults/options" "$root/defaults/gtk-3.0" "$root/defaults/swaync" "$root/options"
    cp "$src"/overlay.mjs "$src"/overlay-cli.mjs "$src"/overlay.sh "$src"/derived.sh "$root/scripts/state/"
    printf 'zen\n' > "$root/defaults/options/browser"
    printf 'nvim\n' > "$root/defaults/options/editor"
    printf '[Settings]\ngtk-theme-name=Kripton\n' > "$root/defaults/gtk-3.0/settings.ini"
    printf '{\n  "timeout": 5\n}\n' > "$root/defaults/swaync/config.json"
    ln -s ../../.cache/current_wallpaper "$root/options/wallpaper"
}

run() { env -u XDG_STATE_HOME HOME="$tmp/home" OVERLAY_STATE_DIR="$tmp/state" bash "$1/scripts/state/overlay.sh" "${@:2}"; }

# No defaults/: a pre-overlay commit. Nothing happens.
mkdir -p "$tmp/old/scripts/state"
cp "$src"/overlay.mjs "$src"/overlay-cli.mjs "$src"/overlay.sh "$src"/derived.sh "$tmp/old/scripts/state/"
run "$tmp/old" sync
assert_eq "$([ -e "$tmp/state" ] && echo yes || echo no)" "no" "no defaults/: nothing is written"

tree="$tmp/cfg"
make_tree "$tree"
run "$tree" sync
assert_eq "$(cat "$tree/options/browser")" "zen" "first sync renders options"
assert_eq "$(cat "$tree/gtk-3.0/settings.ini")" "$(printf '[Settings]\ngtk-theme-name=Kripton')" "first sync renders ini"
assert_eq "$(readlink "$tree/options/wallpaper")" "../../.cache/current_wallpaper" "the wallpaper symlink is untouched"

before=$(stat -c %Y.%i "$tree/options/browser" "$tree/gtk-3.0/settings.ini" "$tree/swaync/config.json")
sleep 1
run "$tree" sync
assert_eq "$(stat -c %Y.%i "$tree/options/browser" "$tree/gtk-3.0/settings.ini" "$tree/swaync/config.json")" "$before" "an unchanged sync rewrites nothing"

echo firefox > "$tree/options/browser"
printf '[Settings]\ngtk-theme-name=Adwaita\n' > "$tree/gtk-3.0/settings.ini"
run "$tree" sync
assert_eq "$(cat "$tmp/state/overrides/options/browser")" "firefox" "a live option edit is harvested"
assert_contains "$(cat "$tmp/state/overrides/gtk-3.0/settings.ini")" "gtk-theme-name=Adwaita" "a live ini edit is harvested"
printf 'helix\n' > "$tree/defaults/options/editor"
run "$tree" sync
assert_eq "$(cat "$tree/options/editor")" "helix" "a new default reaches an unchanged key"
assert_eq "$(cat "$tree/options/browser")" "firefox" "an override survives a default change"

# A malformed live file is skipped untouched; the others still render.
printf '[Settings]\nnot a pair\n' > "$tree/gtk-3.0/settings.ini"
printf 'vim\n' > "$tree/options/editor"
set +e; err=$(run "$tree" sync 2>&1 >/dev/null); status=$?; set -e
assert_eq "$status" "1" "a malformed live file fails the run"
assert_contains "$err" "gtk-3.0/settings.ini" "the failure names the target"
assert_eq "$(cat "$tree/gtk-3.0/settings.ini")" "$(printf '[Settings]\nnot a pair')" "the malformed file is left untouched"
assert_eq "$(cat "$tmp/state/overrides/options/editor")" "vim" "other targets still sync"
printf '[Settings]\ngtk-theme-name=Adwaita\n' > "$tree/gtk-3.0/settings.ini"

# check: an unparseable overrides file is reported.
printf 'garbage\n' > "$tmp/state/overrides/gtk-3.0/settings.ini"
set +e; out=$(run "$tree" check 2>&1); status=$?; set -e
assert_eq "$status" "1" "check fails on a bad overrides file"
assert_contains "$out" "gtk-3.0/settings.ini" "check names the target"
rm "$tmp/state/overrides/gtk-3.0/settings.ini"

# --replace: a live file with no render record is backed up and replaced.
fresh="$tmp/fresh"
make_tree "$fresh"
mkdir -p "$fresh/gtk-3.0"
printf '[Settings]\ngtk-theme-name=Old\n' > "$fresh/gtk-3.0/settings.ini"
env -u XDG_STATE_HOME HOME="$tmp/home" OVERLAY_STATE_DIR="$tmp/state2" bash "$fresh/scripts/state/overlay.sh" sync --replace "$tmp/backup"
assert_eq "$(cat "$tmp/backup/gtk-3.0/settings.ini")" "$(printf '[Settings]\ngtk-theme-name=Old')" "--replace backs up the stale file"
assert_eq "$(cat "$fresh/gtk-3.0/settings.ini")" "$(printf '[Settings]\ngtk-theme-name=Kripton')" "--replace starts from the defaults"
assert_eq "$(readlink "$fresh/options/wallpaper")" "../../.cache/current_wallpaper" "--replace never moves symlinks"

# The lock serialises concurrent runs; both succeed.
run "$tree" sync & first=$!
run "$tree" sync; second=$?
wait "$first"; first=$?
assert_eq "$first:$second" "0:0" "concurrent syncs both succeed"

test_summary state-cli
