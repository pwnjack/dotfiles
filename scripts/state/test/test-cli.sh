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

# --replace '' replaces without any backup.
bare="$tmp/bare"
make_tree "$bare"
mkdir -p "$bare/gtk-3.0" "$tmp/nobackup"
printf '[Settings]\ngtk-theme-name=Old\n' > "$bare/gtk-3.0/settings.ini"
env -u XDG_STATE_HOME HOME="$tmp/home" OVERLAY_STATE_DIR="$tmp/state3" bash "$bare/scripts/state/overlay.sh" sync --replace ''
assert_eq "$(cat "$bare/gtk-3.0/settings.ini")" "$(printf '[Settings]\ngtk-theme-name=Kripton')" "--replace '' replaces the stale file"
assert_eq "$(find "$tmp/nobackup" -mindepth 1 | wc -l)" "0" "--replace '' creates nothing under an unused backup parent"
assert_eq "$([ -e "$tmp/backup3" ] && echo yes || echo no)" "no" "--replace '' creates no backup directory"

# --replace ignores stale live content but keeps recorded overrides.
keep="$tmp/keep"
make_tree "$keep"
mkdir -p "$keep/gtk-3.0" "$tmp/state6/overrides/options" "$tmp/state6/overrides/gtk-3.0"
printf 'firefox\n' > "$tmp/state6/overrides/options/browser"
printf 'old\n' > "$keep/options/browser"
printf '[Settings]\ngtk-theme-name=Adwaita\n' > "$tmp/state6/overrides/gtk-3.0/settings.ini"
printf '[Settings]\ngtk-theme-name=Old\n' > "$keep/gtk-3.0/settings.ini"
env -u XDG_STATE_HOME HOME="$tmp/home" OVERLAY_STATE_DIR="$tmp/state6" bash "$keep/scripts/state/overlay.sh" sync --replace ''
assert_eq "$(cat "$keep/options/browser")" "firefox" "--replace keeps a recorded option override"
assert_eq "$(cat "$tmp/state6/overrides/options/browser")" "firefox" "--replace keeps the option override recorded"
assert_contains "$(cat "$keep/gtk-3.0/settings.ini")" "gtk-theme-name=Adwaita" "--replace keeps a recorded ini override"

# --replace on options: declared keys are replaced, per-machine keys stay live.
opt="$tmp/opt"
make_tree "$opt"
printf 'brave\n' > "$opt/options/browser"
printf 'enabled\n' > "$opt/options/calendar-default"
env -u XDG_STATE_HOME HOME="$tmp/home" OVERLAY_STATE_DIR="$tmp/state4" bash "$opt/scripts/state/overlay.sh" sync --replace "$tmp/backup2"
assert_eq "$(cat "$tmp/backup2/options/browser")" "brave" "--replace backs up a declared option"
assert_eq "$(cat "$opt/options/browser")" "zen" "--replace resets a declared option"
assert_eq "$(cat "$opt/options/calendar-default")" "enabled" "--replace keeps a per-machine option live"
assert_eq "$(cat "$tmp/state4/overrides/options/calendar-default")" "enabled" "--replace records a per-machine option"
assert_eq "$([ -e "$tmp/backup2/options/calendar-default" ] && echo yes || echo no)" "no" "--replace does not back up per-machine options"
assert_eq "$(readlink "$opt/options/wallpaper")" "../../.cache/current_wallpaper" "--replace keeps the wallpaper symlink"

# An unparseable overrides file never costs the live file.
bad="$tmp/bad"
make_tree "$bad"
mkdir -p "$bad/gtk-3.0" "$tmp/state5/overrides/gtk-3.0"
printf '[Settings]\ngtk-theme-name=Old\n' > "$bad/gtk-3.0/settings.ini"
printf 'garbage\n' > "$tmp/state5/overrides/gtk-3.0/settings.ini"
set +e; env -u XDG_STATE_HOME HOME="$tmp/home" OVERLAY_STATE_DIR="$tmp/state5" bash "$bad/scripts/state/overlay.sh" sync --replace '' >/dev/null 2>&1; status=$?; set -e
assert_eq "$status" "1" "a bad overrides file fails a --replace run"
assert_eq "$(cat "$bad/gtk-3.0/settings.ini")" "$(printf '[Settings]\ngtk-theme-name=Old')" "the live file survives a failed --replace"

# A tree that is not ~/.config needs an explicit state directory.
mkdir -p "$tmp/home2"
set +e; err=$(env -u XDG_STATE_HOME -u OVERLAY_STATE_DIR HOME="$tmp/home2" bash "$tree/scripts/state/overlay.sh" sync 2>&1); status=$?; set -e
assert_eq "$status" "1" "a foreign tree without OVERLAY_STATE_DIR is refused"
assert_contains "$err" "OVERLAY_STATE_DIR" "the refusal names the override"
assert_eq "$([ -e "$tmp/home2/.local" ] && echo yes || echo no)" "no" "the refusal creates no state"

# The lock serialises concurrent runs; both succeed.
run "$tree" sync & first=$!
run "$tree" sync; second=$?
wait "$first"; first=$?
assert_eq "$first:$second" "0:0" "concurrent syncs both succeed"

test_summary state-cli
