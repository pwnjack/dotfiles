#!/bin/bash
# apply-font.sh writes the GTK font to gsettings as well as settings.ini.
set -euo pipefail
# The test resolves the shared assertion library from the repository root.
# shellcheck disable=SC1091
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/assert.sh"

real="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/apply-font.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# A copy inside the fixture tree, so config_dir resolves to the fixture.
mkdir -p "$tmp/.config/scripts/fonts"
cp "$real" "$tmp/.config/scripts/fonts/apply-font.sh"
script="$tmp/.config/scripts/fonts/apply-font.sh"
mkdir -p "$tmp/.config/options" "$tmp/.config/rofi/options" "$tmp/.config/gtk-3.0" "$tmp/bin"
echo "Main Font" > "$tmp/.config/options/font"
echo "Gtk Font" > "$tmp/.config/options/font-gtk"
printf '[Settings]\ngtk-font-name=Old 12 @wght=600\n' > "$tmp/.config/gtk-3.0/settings.ini"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/gsettings.log"\n' "$tmp" > "$tmp/bin/gsettings"
chmod +x "$tmp/bin/gsettings"

HOME="$tmp" PATH="$tmp/bin:$PATH" bash "$script" >/dev/null
assert_eq "$(cat "$tmp/gsettings.log")" "set org.gnome.desktop.interface font-name Gtk Font 12 @wght=600" \
    "the GTK font, size and weight reach gsettings"

mkdir -p "$tmp/.config/waybar" "$tmp/.config/ghostty"
printf '* {\n    border: none;\n}\n' > "$tmp/.config/waybar/style.css"
printf 'config-file = ?font\n' > "$tmp/.config/ghostty/config"
style_before=$(cat "$tmp/.config/waybar/style.css"); ghostty_before=$(cat "$tmp/.config/ghostty/config")
HOME="$tmp" PATH="$tmp/bin:$PATH" bash "$script" >/dev/null
assert_eq "$(cat "$tmp/.local/state/rofi/font.rasi")" 'configuration { font: "Main Font 10"; }' "rofi include rendered"
assert_eq "$(cat "$tmp/.local/state/waybar/font.css")" "$(printf '* {\n    font-family: "Main Font", "JetbrainsMono Nerd", "Hack Nerd", sans-serif;\n}')" "waybar include rendered"
assert_eq "$(cat "$tmp/.local/state/ghostty/font")" 'font-family = "Main Font"' "ghostty include rendered"
strata_font="$tmp/.local/state/fontconfig/strata-font.conf"
assert_contains "$(cat "$strata_font")" '<string>Main Font</string></edit>' "Strata fontconfig include uses the option font"
assert_contains "$(cat "$strata_font")" '<test name="prgname"><string>io.github.lgse.Strata</string></test>' "Strata fontconfig include matches its application ID"
assert_contains "$(cat "$strata_font")" '<test name="family"><string>JetBrains Mono</string></test>' "Strata fontconfig include replaces only its bundled font"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$strata_font"
    pass "Strata fontconfig include is valid XML"
fi
assert_eq "$(cat "$tmp/.config/waybar/style.css")" "$style_before" "style.css is never edited"
assert_eq "$(cat "$tmp/.config/ghostty/config")" "$ghostty_before" "ghostty/config is never edited"

rm -rf "$tmp/.local/state" "$tmp/gsettings.log"
rm "$tmp/.config/options/font"
gtk_before=$(cat "$tmp/.config/gtk-3.0/settings.ini")
HOME="$tmp" PATH="$tmp/bin:$PATH" bash "$script" --includes >/dev/null
assert_contains "$(cat "$tmp/.local/state/rofi/font.rasi")" "FiraCode Nerd Font" "--includes falls back to the default font"
assert_contains "$(cat "$strata_font")" '<string>FiraCode Nerd Font</string></edit>' "--includes renders Strata fontconfig with the fallback font"
assert_eq "$(cat "$tmp/.config/gtk-3.0/settings.ini")" "$gtk_before" "--includes leaves GTK alone"
assert_eq "$([ -e "$tmp/gsettings.log" ] && echo yes || echo no)" "no" "--includes leaves gsettings alone"
echo 'Font & Family' > "$tmp/.config/options/font"
HOME="$tmp" PATH="$tmp/bin:$PATH" bash "$script" --includes >/dev/null
assert_contains "$(cat "$strata_font")" '<string>Font &amp; Family</string>' "Strata fontconfig XML-escapes ampersands"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$strata_font"
    pass "Strata fontconfig include with an ampersand is valid XML"
fi
echo "Main Font" > "$tmp/.config/options/font"

printf '#!/bin/sh\nexit 1\n' > "$tmp/bin/gsettings"
if HOME="$tmp" PATH="$tmp/bin:$PATH" bash "$script" >/dev/null 2>&1; then
    fail "a failed gsettings write must fail the script"
else
    pass "a failed gsettings write fails the script"
fi
test_summary
