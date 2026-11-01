#!/bin/bash
# Acceptance for the machine-state overlay: no kind of setting change leaves a
# tracked file modified. Runs on a private copy of the tracked tree (from the
# index, so it also works in the pre-commit snapshot) under a throwaway HOME.
set -euo pipefail
repo="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
source "$repo/scripts/lib/assert.sh"
command -v node >/dev/null && command -v jq >/dev/null || { echo "  skip: machine-state acceptance (needs node and jq)"; exit 0; }
# Every write below must land under the throwaway HOME: overlay.sh prefers
# OVERLAY_STATE_DIR (and it bypasses the tree guard) over XDG_STATE_HOME.
unset XDG_STATE_HOME OVERLAY_STATE_DIR

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
home="$tmp/home"; cfg="$home/.config"
mkdir -p "$cfg" "$tmp/bin"
git -C "$repo" checkout-index -a --prefix="$cfg/"
rm -rf "$cfg/wallpapers"
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/gsettings"; chmod +x "$tmp/bin/gsettings"
g() { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$cfg" -c user.name=t -c user.email=t@t "$@"; }
g init -q
# Track exactly what the real index tracks, whatever the copied .gitignore says.
git -C "$repo" ls-files -z | grep -zv '^wallpapers/' | g add -f --pathspec-from-file=- --pathspec-file-nul
g commit -qm base
want=$(git -C "$repo" ls-files -z | grep -zv '^wallpapers/' | tr -cd '\0' | wc -c)
assert_eq "$(g ls-files -z | tr -cd '\0' | wc -c)" "$want" "the private repo tracks exactly the index"
ov_sync() { HOME="$home" PATH="$tmp/bin:$PATH" bash "$cfg/scripts/state/overlay.sh" sync "$@"; }

ov_sync --replace ''
assert_eq "$(g status --porcelain)" "" "a first render leaves git clean"
assert_eq "$([ -d "$home/.local/state/dotfiles/last" ] && echo yes || echo no)" "yes" "the first render records last-rendered state"
assert_eq "$(find "$home/.local/state/dotfiles/overrides" -type f 2>/dev/null)" "" "a first render records no overrides"
for live in options/browser gtk-3.0/settings.ini gtk-4.0/settings.ini qt5ct/qt5ct.conf qt6ct/qt6ct.conf mimeapps.list swaync/config.json hypr/hyprsunset.conf; do
    assert_eq "$([ -f "$cfg/$live" ] && echo yes || echo no)" "yes" "$live is rendered"
done

# A crash between write and rename leaves overlay-cli.mjs's temporary file,
# holding this machine's settings, beside every kind of live file.
temps=()
while IFS= read -r -d '' live; do
    case "$live" in */*) temp="${live%/*}/.${live##*/}.overlay-tmp" ;; *) temp=".$live.overlay-tmp" ;; esac
    printf 'machine settings\n' > "$cfg/$temp"
    temps+=("$cfg/$temp")
done < <(cd "$cfg/defaults" && find . -mindepth 1 -type f ! -name '.*' -printf '%P\0')
assert_eq "$(g status --porcelain)" "" "the overlay's temporary files are ignored by git (${#temps[@]} targets)"
rm -f -- "${temps[@]}"

echo firefox > "$cfg/options/browser"
sed -i 's|^x-scheme-handler/https=.*|x-scheme-handler/https=firefox.desktop|' "$cfg/mimeapps.list"
sed -i '/^\[Default Applications\]/a x-scheme-handler/ftp=firefox.desktop' "$cfg/mimeapps.list"
sed -i 's/^style=.*/style=Fusion/' "$cfg/qt5ct/qt5ct.conf"
jq '.timeout = 9' "$cfg/swaync/config.json" > "$tmp/sw" && mv "$tmp/sw" "$cfg/swaync/config.json"
sed -i 's/^\$night_temp = .*/$night_temp = 3500/' "$cfg/hypr/hyprsunset.conf"
echo "Hack Nerd Font" > "$cfg/options/font"
echo "Hack Nerd Font" > "$cfg/options/font-gtk"
HOME="$home" PATH="$tmp/bin:$PATH" bash "$cfg/scripts/fonts/apply-font.sh" >/dev/null
mkdir -p "$home/.local/state/hypr" && printf '$lock_timeout = 900\n' > "$home/.local/state/hypr/hypridle.conf"
ov_sync

assert_eq "$(g status --porcelain)" "" "every kind of change leaves git clean"
assert_eq "$(cat "$cfg/options/browser")" "firefox" "the option change persists"
assert_eq "$(sed -n '/^\[Default Applications\]/,/^\[/p' "$cfg/mimeapps.list" | grep -c '^x-scheme-handler/https=firefox.desktop')" "1" "the changed MIME default persists in [Default Applications]"
assert_contains "$(cat "$cfg/mimeapps.list")" "x-scheme-handler/ftp=firefox.desktop" "the app's new MIME key persists"
assert_contains "$(cat "$cfg/qt5ct/qt5ct.conf")" "style=Fusion" "the Qt change persists"
assert_eq "$(jq .timeout "$cfg/swaync/config.json")" "9" "the swaync change persists"
assert_contains "$(cat "$cfg/hypr/hyprsunset.conf")" '$night_temp = 3500' "the night light change persists"
assert_contains "$(cat "$home/.local/state/hypr/hypridle.conf")" '$lock_timeout = 900' "the hypridle state file persists"
assert_contains "$(cat "$cfg/hypr/hypridle.conf")" 'source = ~/.local/state/hypr/hypridle.conf' "hypridle.conf sources the state file"
for gtk in gtk-3.0 gtk-4.0; do
    assert_contains "$(cat "$cfg/$gtk/settings.ini")" "gtk-font-name=Hack Nerd Font" "the font reaches $gtk"
done
assert_contains "$(cat "$home/.local/state/waybar/font.css")" "Hack Nerd Font" "the font reaches Waybar's include"

printf 'helix\n' > "$cfg/defaults/options/editor"
sed -i 's/^custom_palette=.*/custom_palette=true/' "$cfg/defaults/qt5ct/qt5ct.conf"
g commit -qam "new editor default"
ov_sync
assert_eq "$(cat "$cfg/options/editor")" "helix" "a new repo default reaches an unchanged key"
assert_eq "$(cat "$cfg/options/browser")" "firefox" "an override survives a new default"
assert_contains "$(cat "$cfg/qt5ct/qt5ct.conf")" "custom_palette=true" "a new file-format default arrives"
assert_contains "$(cat "$cfg/qt5ct/qt5ct.conf")" "style=Fusion" "the Qt override survives a new default"
assert_eq "$(jq .timeout "$cfg/swaync/config.json")" "9" "the swaync change survives the second sync"
assert_contains "$(cat "$cfg/mimeapps.list")" "x-scheme-handler/ftp=firefox.desktop" "the MIME key survives the second sync"
assert_contains "$(cat "$cfg/hypr/hyprsunset.conf")" '$night_temp = 3500' "the night light change survives the second sync"
assert_eq "$(g status --porcelain)" "" "still clean after the default change"
test_summary machine-state
