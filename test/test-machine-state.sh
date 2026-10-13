#!/bin/bash
# Acceptance for the machine-state overlay: no kind of setting change leaves a
# tracked file modified. Runs on a private copy of the tracked tree (from the
# index, so it also works in the pre-commit snapshot) under a throwaway HOME.
set -euo pipefail
repo="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
source "$repo/scripts/lib/assert.sh"
command -v node >/dev/null && command -v jq >/dev/null || { echo "  skip machine-state acceptance (needs node and jq)"; exit 0; }
unset XDG_STATE_HOME # every write below must land under the throwaway HOME

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
home="$tmp/home"; cfg="$home/.config"
mkdir -p "$cfg" "$tmp/bin"
while IFS= read -r -d '' path; do
    case "$path" in wallpapers/*) continue ;; esac
    mkdir -p "$cfg/$(dirname "$path")"
    cp -P -- "$repo/$path" "$cfg/$path"
done < <(git -C "$repo" ls-files -z)
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/gsettings"; chmod +x "$tmp/bin/gsettings"
g() { git -C "$cfg" -c user.name=t -c user.email=t@t "$@"; }
g init -q && g add -A && g commit -qm base
sync() { HOME="$home" PATH="$tmp/bin:$PATH" bash "$cfg/scripts/state/overlay.sh" sync "$@"; }

sync --replace ''
assert_eq "$(g status --porcelain)" "" "a first render leaves git clean"
assert_eq "$(find "$home/.local/state/dotfiles/overrides" -type f 2>/dev/null)" "" "a first render records no overrides"
for live in options/browser gtk-3.0/settings.ini gtk-4.0/settings.ini qt5ct/qt5ct.conf qt6ct/qt6ct.conf mimeapps.list swaync/config.json hypr/hyprsunset.conf; do
    assert_eq "$([ -f "$cfg/$live" ] && echo yes || echo no)" "yes" "$live is rendered"
done

echo firefox > "$cfg/options/browser"
sed -i 's|^x-scheme-handler/https=.*|x-scheme-handler/https=firefox.desktop|' "$cfg/mimeapps.list"
sed -i '/^\[Default Applications\]/a x-scheme-handler/ftp=firefox.desktop' "$cfg/mimeapps.list"
sed -i 's/^style=.*/style=Fusion/' "$cfg/qt5ct/qt5ct.conf"
jq '.timeout = 9' "$cfg/swaync/config.json" > "$tmp/sw" && mv "$tmp/sw" "$cfg/swaync/config.json"
sed -i 's/^\$night_temp = .*/$night_temp = 3500/' "$cfg/hypr/hyprsunset.conf"
echo "Hack Nerd Font" > "$cfg/options/font"
HOME="$home" PATH="$tmp/bin:$PATH" bash "$cfg/scripts/fonts/apply-font.sh" >/dev/null
mkdir -p "$home/.local/state/hypr" && printf '$lock_timeout = 900\n' > "$home/.local/state/hypr/hypridle.conf"
sync

assert_eq "$(g status --porcelain)" "" "every kind of change leaves git clean"
assert_eq "$(cat "$cfg/options/browser")" "firefox" "the option change persists"
assert_contains "$(cat "$cfg/mimeapps.list")" "x-scheme-handler/https=firefox.desktop" "the app's changed MIME default persists"
assert_contains "$(cat "$cfg/mimeapps.list")" "x-scheme-handler/ftp=firefox.desktop" "the app's new MIME key persists"
assert_contains "$(cat "$cfg/qt5ct/qt5ct.conf")" "style=Fusion" "the Qt change persists"
assert_eq "$(jq .timeout "$cfg/swaync/config.json")" "9" "the swaync change persists"
assert_contains "$(cat "$cfg/hypr/hyprsunset.conf")" '$night_temp = 3500' "the night light change persists"
assert_contains "$(cat "$home/.local/state/waybar/font.css")" "Hack Nerd Font" "the font reaches Waybar's include"

printf 'helix\n' > "$cfg/defaults/options/editor"
g commit -qam "new editor default"
sync
assert_eq "$(cat "$cfg/options/editor")" "helix" "a new repo default reaches an unchanged key"
assert_eq "$(cat "$cfg/options/browser")" "firefox" "an override survives a new default"
assert_eq "$(g status --porcelain)" "" "still clean after the default change"
test_summary machine-state
