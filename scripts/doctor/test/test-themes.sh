# Tests for scripts/doctor/checks/themes.sh — sourced by run-tests.sh
# shellcheck shell=bash

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/themes.sh"

# --- the check, with the host probe stubbed --------------------------------
thm_installed=" gtk:Kripton icon:Papirus-Dark cursor:Bibata kvantum:Carl "
_thm_present() { [[ $thm_installed == *" $1:$2 "* ]]; }

thm_root="$(make_fixture)"
mkdir -p "$thm_root/defaults/gtk-3.0" "$thm_root/defaults/gtk-4.0" "$thm_root/defaults/qt5ct" \
    "$thm_root/defaults/qt6ct" "$thm_root/defaults/options" "$thm_root/gtk-3.0" "$thm_root/Kvantum"
printf '[Settings]\ngtk-theme-name=Kripton\ngtk-icon-theme-name=Papirus-Dark\ngtk-cursor-theme-name=Bibata\n' > "$thm_root/defaults/gtk-3.0/settings.ini"
printf '[Settings]\r\ngtk-theme-name = Kripton \r\ngtk-icon-theme-name=Papirus-Dark\r\ngtk-cursor-theme-name=Bibata\r\n' > "$thm_root/defaults/gtk-4.0/settings.ini"
printf '[Interface]\nicon_theme=NotThis\n[Appearance]\nicon_theme=Papirus-Dark\nstyle=kvantum\n' > "$thm_root/defaults/qt5ct/qt5ct.conf"
printf '[Appearance]\nicon_theme=Papirus-Dark\n' > "$thm_root/defaults/qt6ct/qt6ct.conf"
printf 'Bibata\n' > "$thm_root/defaults/options/cursortheme"
git -C "$thm_root" add defaults

thm_saved_root="$DOCTOR_ROOT"
DOCTOR_ROOT="$thm_root"
thm_run() {
    doctor_reset
    check_themes > "$DOCTOR_TEST_TMP/themes.out" 2>&1
    thm_text="$(cat "$DOCTOR_TEST_TMP/themes.out")"
}

thm_run
assert_eq "$DOCTOR_WARNINGS" "0" "themes: everything selected is installed, nothing is reported"
assert_contains "$thm_text" "Every selected GTK, icon, cursor and Kvantum theme is installed" "themes: all-clear when nothing is missing"

# Each kind missing on its own: one finding, naming the file that selects it.
thm_installed=" icon:Papirus-Dark cursor:Bibata "
thm_run
assert_eq "$DOCTOR_WARNINGS" "1" "themes: a missing GTK theme is one finding for both GTK versions"
assert_contains "$thm_text" "No GTK theme 'Kripton', which defaults/gtk-3.0/settings.ini, defaults/gtk-4.0/settings.ini select" "themes: names the GTK theme and every file selecting it (CRLF and spaces trimmed)"
assert_contains "$thm_text" "pacman -F usr/share/themes/Kripton/gtk-3.0/gtk.css" "themes: the GTK hint names a file to look up"
assert_not_contains "$thm_text" "✓" "themes: no all-clear with findings"

thm_installed=" gtk:Kripton cursor:Bibata "
thm_run
assert_eq "$DOCTOR_WARNINGS" "1" "themes: a missing icon theme is one finding across GTK and Qt files"
assert_contains "$thm_text" "No icon theme 'Papirus-Dark', which defaults/gtk-3.0/settings.ini, defaults/gtk-4.0/settings.ini, defaults/qt5ct/qt5ct.conf, defaults/qt6ct/qt6ct.conf select" "themes: names every file selecting the icon theme"
assert_not_contains "$thm_text" "NotThis" "themes: only [Appearance] icon_theme counts"
assert_contains "$thm_text" "pacman -F usr/share/icons/Papirus-Dark/index.theme" "themes: the icon hint names a file to look up"

thm_installed=" gtk:Kripton icon:Papirus-Dark "
thm_run
assert_eq "$DOCTOR_WARNINGS" "1" "themes: a missing cursor theme is one finding across the option and GTK files"
assert_contains "$thm_text" "No cursor theme 'Bibata', which defaults/gtk-3.0/settings.ini, defaults/gtk-4.0/settings.ini, defaults/options/cursortheme select" "themes: names every file selecting the cursor theme"

# A live file overrides its default.
mkdir -p "$thm_root/options"
printf '\n' > "$thm_root/options/cursortheme"
thm_installed=" gtk:Kripton icon:Papirus-Dark cursor:Bibata "
thm_run
assert_eq "$DOCTOR_WARNINGS" "0" "themes: an empty live cursor option selects nothing"
printf 'LiveCursor\n' > "$thm_root/options/cursortheme"
thm_run
assert_contains "$thm_text" "No cursor theme 'LiveCursor', which options/cursortheme select" "themes: the live option wins over its default"
rm -r "$thm_root/options"

# Kvantum has no tracked default: nothing is read until the live file exists.
thm_run
assert_eq "$DOCTOR_WARNINGS" "0" "themes: no Kvantum file, no Kvantum finding"
printf '[General]\ntheme=Carl\n' > "$thm_root/Kvantum/kvantum.kvconfig"
thm_run
assert_eq "$DOCTOR_WARNINGS" "1" "themes: a missing Kvantum theme is reported"
assert_contains "$thm_text" "No Kvantum theme 'Carl', which Kvantum/kvantum.kvconfig selects" "themes: names the Kvantum theme and file"
assert_contains "$thm_text" "pacman -F usr/share/Kvantum/Carl/Carl.kvconfig" "themes: the Kvantum hint names a file to look up"
thm_installed=" gtk:Kripton icon:Papirus-Dark cursor:Bibata kvantum:Carl "
thm_run
assert_eq "$DOCTOR_WARNINGS" "0" "themes: an installed Kvantum theme is fine"
printf '[General]\ntheme=default\n' > "$thm_root/Kvantum/kvantum.kvconfig"
thm_installed=" gtk:Kripton icon:Papirus-Dark cursor:Bibata "
thm_run
assert_eq "$DOCTOR_WARNINGS" "0" "themes: Kvantum's built-in default needs nothing"

# A name with a space is quoted in the hint.
printf '[Settings]\ngtk-theme-name=My Theme\n' > "$thm_root/gtk-3.0/settings.ini"
thm_run
assert_contains "$thm_text" "pacman -F usr/share/themes/My\\ Theme/gtk-3.0/gtk.css" "themes: every hint path goes through doctor_q"
assert_not_contains "$thm_text" "<" "themes: no placeholder text in hints"
DOCTOR_ROOT="$thm_saved_root"

# --- the real probe, against a private fixture ------------------------------
unset -f _thm_present
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/themes.sh"
thm_home="$DOCTOR_TEST_TMP/thm-home"
thm_share="$DOCTOR_TEST_TMP/thm-share"
mkdir -p "$thm_home/.themes/UserGtk/gtk-3.0" "$thm_home/.local/share/themes/LocalGtk/gtk-4.0" \
    "$thm_share/themes/SysGtk/gtk-3.0" "$thm_share/themes/NoGtk/other" \
    "$thm_home/.icons/UserIcons" "$thm_home/.local/share/icons/LocalIcons" "$thm_share/icons/SysIcons" \
    "$thm_share/icons/OnlyCursor/cursors" "$thm_share/icons/NoCursors" \
    "$thm_home/.config/Kvantum/UserKv" "$thm_share/Kvantum/SysKv" "$thm_share/Kvantum/BadKv"
: > "$thm_home/.icons/UserIcons/index.theme"
: > "$thm_home/.local/share/icons/LocalIcons/index.theme"
: > "$thm_share/icons/SysIcons/index.theme"
: > "$thm_share/icons/NoCursors/index.theme"
: > "$thm_home/.config/Kvantum/UserKv/UserKv.kvconfig"
: > "$thm_share/Kvantum/SysKv/SysKv.kvconfig"
: > "$thm_share/Kvantum/BadKv/Other.kvconfig"
thm_saved_home="${DOCTOR_THEME_HOME-}"
thm_saved_share="${DOCTOR_THEME_SHARE-}"
DOCTOR_THEME_HOME="$thm_home"
DOCTOR_THEME_SHARE="$thm_share"
thm_probe() { _thm_present "$1" "$2" && thm_r=found || thm_r=missing; }
thm_probe gtk UserGtk;  assert_eq "$thm_r" found "themes: GTK theme found in ~/.themes"
thm_probe gtk LocalGtk; assert_eq "$thm_r" found "themes: GTK theme found in ~/.local/share/themes"
thm_probe gtk SysGtk;   assert_eq "$thm_r" found "themes: GTK theme found in /usr/share/themes"
thm_probe gtk NoGtk;    assert_eq "$thm_r" missing "themes: a theme directory without gtk-3.0 or gtk-4.0 is not a GTK theme"
thm_probe gtk Adwaita;  assert_eq "$thm_r" found "themes: GTK's built-in Adwaita needs no directory"
thm_probe gtk Nothing;  assert_eq "$thm_r" missing "themes: an unknown GTK theme is missing"
thm_probe icon UserIcons;  assert_eq "$thm_r" found "themes: icon theme found in ~/.icons"
thm_probe icon LocalIcons; assert_eq "$thm_r" found "themes: icon theme found in ~/.local/share/icons"
thm_probe icon SysIcons;   assert_eq "$thm_r" found "themes: icon theme found in /usr/share/icons"
thm_probe icon OnlyCursor; assert_eq "$thm_r" missing "themes: an icon theme needs an index.theme"
thm_probe cursor OnlyCursor; assert_eq "$thm_r" found "themes: a cursor theme needs a cursors directory"
thm_probe cursor NoCursors;  assert_eq "$thm_r" missing "themes: an icon theme without cursors is not a cursor theme"
thm_probe kvantum UserKv; assert_eq "$thm_r" found "themes: Kvantum theme found in ~/.config/Kvantum"
thm_probe kvantum SysKv;  assert_eq "$thm_r" found "themes: Kvantum theme found in /usr/share/Kvantum"
thm_probe kvantum BadKv;  assert_eq "$thm_r" missing "themes: a Kvantum theme needs <name>/<name>.kvconfig"
thm_probe gtk ../themes/SysGtk; assert_eq "$thm_r" missing "themes: a name holding / is never a theme"
DOCTOR_THEME_HOME="$thm_saved_home"
DOCTOR_THEME_SHARE="$thm_saved_share"
[ -n "$thm_saved_home" ] || unset DOCTOR_THEME_HOME
[ -n "$thm_saved_share" ] || unset DOCTOR_THEME_SHARE
