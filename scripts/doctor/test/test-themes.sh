# Tests for scripts/doctor/checks/themes.sh — sourced by run-tests.sh
# shellcheck shell=bash

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/themes.sh"

# --- the check, with the host probe stubbed --------------------------------
thm_installed=" gtk:Kripton icon:Papirus-Dark cursor:Bibata kvantum:Carl "
_thm_present() { [[ $thm_installed == *" $1:$2 "* ]]; }
thm_gs=""
_thm_gsettings() { [[ $thm_gs == *" $1="* ]] || return 0; local v="${thm_gs#* "$1"=}"; printf '%s' "${v%% *}"; }

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
assert_contains "$thm_text" "No GTK theme 'Kripton', selected by defaults/gtk-3.0/settings.ini, defaults/gtk-4.0/settings.ini" "themes: names the GTK theme and every file selecting it (CRLF and spaces trimmed)"
assert_contains "$thm_text" "pacman -F usr/share/themes/Kripton/gtk-3.0/gtk.css" "themes: the GTK hint names a file to look up"
assert_not_contains "$thm_text" "✓" "themes: no all-clear with findings"

thm_installed=" gtk:Kripton cursor:Bibata "
thm_run
assert_eq "$DOCTOR_WARNINGS" "1" "themes: a missing icon theme is one finding across GTK and Qt files"
assert_contains "$thm_text" "No icon theme 'Papirus-Dark', selected by defaults/gtk-3.0/settings.ini, defaults/gtk-4.0/settings.ini, defaults/qt5ct/qt5ct.conf, defaults/qt6ct/qt6ct.conf" "themes: names every file selecting the icon theme"
assert_not_contains "$thm_text" "NotThis" "themes: only [Appearance] icon_theme counts"
assert_contains "$thm_text" "pacman -F usr/share/icons/Papirus-Dark/index.theme" "themes: the icon hint names a file to look up"

thm_installed=" gtk:Kripton icon:Papirus-Dark "
thm_run
assert_eq "$DOCTOR_WARNINGS" "1" "themes: a missing cursor theme is one finding across the option and GTK files"
assert_contains "$thm_text" "No cursor theme 'Bibata', selected by defaults/gtk-3.0/settings.ini, defaults/gtk-4.0/settings.ini, defaults/options/cursortheme" "themes: names every file selecting the cursor theme"

# A live file overrides its default.
mkdir -p "$thm_root/options"
printf '\n' > "$thm_root/options/cursortheme"
thm_installed=" gtk:Kripton icon:Papirus-Dark cursor:Bibata "
thm_run
assert_eq "$DOCTOR_WARNINGS" "0" "themes: an empty live cursor option falls back to the default, which is installed"
thm_installed=" gtk:Kripton icon:Papirus-Dark "
thm_run
assert_contains "$thm_text" "No cursor theme 'Bibata', selected by defaults/gtk-3.0/settings.ini, defaults/gtk-4.0/settings.ini, defaults/options/cursortheme" "themes: an empty live cursor option still selects the default's theme"
thm_installed=" gtk:Kripton icon:Papirus-Dark cursor:Bibata "
printf 'LiveCursor\n' > "$thm_root/options/cursortheme"
thm_run
assert_contains "$thm_text" "No cursor theme 'LiveCursor', selected by options/cursortheme" "themes: the live option wins over its default"
rm -r "$thm_root/options"

# gsettings is a selection source of its own.
thm_gs=" gtk-theme=GsGtk icon-theme=GsIcons cursor-theme=GsCursor"
thm_run
assert_eq "$DOCTOR_WARNINGS" "3" "themes: a missing gsettings GTK, icon and cursor theme are each reported"
assert_contains "$thm_text" "No GTK theme 'GsGtk', selected by gsettings org.gnome.desktop.interface gtk-theme" "themes: names the gsettings GTK key"
assert_contains "$thm_text" "No icon theme 'GsIcons', selected by gsettings org.gnome.desktop.interface icon-theme" "themes: names the gsettings icon key"
assert_contains "$thm_text" "No cursor theme 'GsCursor', selected by gsettings org.gnome.desktop.interface cursor-theme" "themes: names the gsettings cursor key"
thm_gs=" gtk-theme=Kripton"
thm_run
assert_eq "$DOCTOR_WARNINGS" "0" "themes: an installed gsettings theme adds nothing"
thm_gs=""

# The AUR defaults have no pacman -F answer, so the hint says where they come from.
thm_installed=" icon:Papirus-Dark cursor:Bibata "
thm_run
assert_contains "$thm_text" "AUR_PACKAGES" "themes: the GTK hint points at the AUR packages"
thm_installed=" gtk:Kripton icon:Papirus-Dark cursor:Bibata "

# Kvantum has no tracked default: nothing is read until the live file exists.
thm_run
assert_eq "$DOCTOR_WARNINGS" "0" "themes: no Kvantum file, no Kvantum finding"
printf '[General]\ntheme=Carl\n' > "$thm_root/Kvantum/kvantum.kvconfig"
thm_run
assert_eq "$DOCTOR_WARNINGS" "1" "themes: a missing Kvantum theme is reported"
assert_contains "$thm_text" "No Kvantum theme 'Carl', selected by Kvantum/kvantum.kvconfig" "themes: names the Kvantum theme and file"
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
thm_share2="$DOCTOR_TEST_TMP/thm-share2"
mkdir -p "$thm_share2/themes/Sys2Gtk/gtk-3.0" "$thm_share2/icons/Sys2Icons" "$thm_share2/Kvantum/Sys2Kv" \
    "$thm_share/icons/Inherits" "$thm_share/icons/InheritsTwo" "$thm_share/icons/InheritsNone" \
    "$thm_share/icons/CycleA" "$thm_share/icons/CycleB" "$thm_share/icons/NoDirs" \
    "$thm_share/Kvantum/Foo" "$thm_share/themes/Bundled/Kvantum" "$thm_share/themes/Bundled/gtk-3.0"
mkdir -p "$thm_home/.themes/UserGtk/gtk-3.0" "$thm_home/.local/share/themes/LocalGtk/gtk-4.0" \
    "$thm_share/themes/SysGtk/gtk-3.0" "$thm_share/themes/NoGtk/other" \
    "$thm_home/.icons/UserIcons" "$thm_home/.local/share/icons/LocalIcons" "$thm_share/icons/SysIcons" \
    "$thm_share/icons/OnlyCursor/cursors" "$thm_share/icons/NoCursors" \
    "$thm_home/.config/Kvantum/UserKv" "$thm_share/Kvantum/SysKv" "$thm_share/Kvantum/BadKv"
printf 'Directories=16x16\n' > "$thm_home/.icons/UserIcons/index.theme"
printf 'Directories=16x16\n' > "$thm_home/.local/share/icons/LocalIcons/index.theme"
printf '[Icon Theme]\nDirectories=16x16\n' > "$thm_share/icons/SysIcons/index.theme"
printf 'Directories=16x16\n' > "$thm_share2/icons/Sys2Icons/index.theme"
printf '[Icon Theme]\nName=No dirs\n' > "$thm_share/icons/NoDirs/index.theme"
printf '[Icon Theme]\nInherits=NoCursors, OnlyCursor\n' > "$thm_share/icons/Inherits/index.theme"
printf '[Icon Theme]\nInherits=Inherits\n' > "$thm_share/icons/InheritsTwo/index.theme"
printf '[Icon Theme]\nInherits=NoCursors\n' > "$thm_share/icons/InheritsNone/index.theme"
printf '[Icon Theme]\nInherits=CycleB\n' > "$thm_share/icons/CycleA/index.theme"
printf '[Icon Theme]\nInherits=CycleA\n' > "$thm_share/icons/CycleB/index.theme"
: > "$thm_share/Kvantum/Foo/Foo.kvconfig"
: > "$thm_share/Kvantum/Foo/FooDark.kvconfig"
: > "$thm_share/themes/Bundled/Kvantum/Bundled.kvconfig"
: > "$thm_share2/Kvantum/Sys2Kv/Sys2Kv.kvconfig"
: > "$thm_home/.config/Kvantum/UserKv/UserKv.kvconfig"
: > "$thm_share/Kvantum/SysKv/SysKv.kvconfig"
: > "$thm_share/Kvantum/BadKv/Other.kvconfig"
printf '[Icon Theme]\nDirectories=16x16\n' > "$thm_share/icons/NoCursors/index.theme"
thm_saved_home="${DOCTOR_THEME_HOME-}"
thm_saved_share="${DOCTOR_THEME_SHARE-}"
DOCTOR_THEME_HOME="$thm_home"
DOCTOR_THEME_SHARE="$thm_share:$thm_share2"
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
thm_probe icon NoDirs; assert_eq "$thm_r" missing "themes: an icon theme needs a Directories= line"
thm_probe cursor OnlyCursor; assert_eq "$thm_r" found "themes: a cursor theme needs a cursors directory"
thm_probe cursor NoCursors;  assert_eq "$thm_r" missing "themes: an icon theme without cursors is not a cursor theme"
thm_probe kvantum UserKv; assert_eq "$thm_r" found "themes: Kvantum theme found in ~/.config/Kvantum"
thm_probe kvantum SysKv;  assert_eq "$thm_r" found "themes: Kvantum theme found in /usr/share/Kvantum"
thm_probe kvantum BadKv;  assert_eq "$thm_r" missing "themes: a Kvantum theme needs <name>/<name>.kvconfig"
thm_probe gtk Sys2Gtk; assert_eq "$thm_r" found "themes: GTK theme found in a second XDG data dir"
thm_probe icon Sys2Icons; assert_eq "$thm_r" found "themes: icon theme found in a second XDG data dir"
thm_probe kvantum Sys2Kv; assert_eq "$thm_r" found "themes: Kvantum theme found in a second XDG data dir"
thm_probe gtk Default-dark; assert_eq "$thm_r" found "themes: GTK 4's built-in Default-dark needs no directory"
thm_probe gtk Default-hc-dark; assert_eq "$thm_r" found "themes: GTK 4's built-in Default-hc-dark needs no directory"
thm_probe cursor Inherits; assert_eq "$thm_r" found "themes: a cursor theme that inherits one with cursors is installed"
thm_probe cursor InheritsTwo; assert_eq "$thm_r" found "themes: cursor inheritance follows a chain"
thm_probe cursor InheritsNone; assert_eq "$thm_r" missing "themes: inheriting a theme without cursors is not a cursor theme"
thm_probe cursor CycleA; assert_eq "$thm_r" missing "themes: an Inherits cycle ends"
thm_probe kvantum FooDark; assert_eq "$thm_r" found "themes: a FooDark Kvantum variant lives in Foo/"
thm_probe kvantum Bundled; assert_eq "$thm_r" found "themes: a Kvantum theme bundled in a GTK theme folder"
thm_probe kvantum Dark; assert_eq "$thm_r" missing "themes: a Kvantum theme named only Dark has no base folder"
thm_probe gtk ../themes/SysGtk; assert_eq "$thm_r" missing "themes: a name holding / is never a theme"
# With no fixture share list, XDG_DATA_HOME, XDG_DATA_DIRS and XDG_CONFIG_HOME apply.
thm_xdg="$DOCTOR_TEST_TMP/thm-xdg"
mkdir -p "$thm_xdg/data/themes/XdgGtk/gtk-3.0" "$thm_xdg/dirs/icons/XdgIcons" "$thm_xdg/cfg/Kvantum/XdgKv"
printf 'Directories=16x16\n' > "$thm_xdg/dirs/icons/XdgIcons/index.theme"
: > "$thm_xdg/cfg/Kvantum/XdgKv/XdgKv.kvconfig"
unset DOCTOR_THEME_HOME DOCTOR_THEME_SHARE
thm_saved_dh="${XDG_DATA_HOME:-}" thm_saved_dd="${XDG_DATA_DIRS:-}" thm_saved_ch="${XDG_CONFIG_HOME:-}"
export XDG_DATA_HOME="$thm_xdg/data" XDG_DATA_DIRS="/nonexistent:$thm_xdg/dirs" XDG_CONFIG_HOME="$thm_xdg/cfg"
thm_probe gtk XdgGtk; assert_eq "$thm_r" found "themes: GTK theme found in XDG_DATA_HOME"
thm_probe icon XdgIcons; assert_eq "$thm_r" found "themes: icon theme found in XDG_DATA_DIRS"
thm_probe kvantum XdgKv; assert_eq "$thm_r" found "themes: Kvantum theme found in XDG_CONFIG_HOME"
if [ -n "$thm_saved_dh" ]; then XDG_DATA_HOME="$thm_saved_dh"; else unset XDG_DATA_HOME; fi
if [ -n "$thm_saved_dd" ]; then XDG_DATA_DIRS="$thm_saved_dd"; else unset XDG_DATA_DIRS; fi
if [ -n "$thm_saved_ch" ]; then XDG_CONFIG_HOME="$thm_saved_ch"; else unset XDG_CONFIG_HOME; fi

# The real gsettings probe, against a fake gsettings and a PATH without one.
thm_bin="$DOCTOR_TEST_TMP/thm-bin"
mkdir -p "$thm_bin" "$DOCTOR_TEST_TMP/thm-nobin"
printf '#!/bin/sh\n[ "$3" = gtk-theme ] && echo "'"'"'Fake Theme'"'"'" && exit 0\nexit 1\n' > "$thm_bin/gsettings"
chmod +x "$thm_bin/gsettings"
thm_saved_path="$PATH"
PATH="$thm_bin:$PATH"
assert_eq "$(_thm_gsettings gtk-theme)" "Fake Theme" "themes: gsettings' quotes are stripped"
assert_eq "$(_thm_gsettings icon-theme)" "" "themes: a failing gsettings selects nothing"
ln -s "$(command -v timeout)" "$DOCTOR_TEST_TMP/thm-nobin/timeout"
export PATH="$DOCTOR_TEST_TMP/thm-nobin"
thm_out="$(_thm_gsettings gtk-theme 2>&1)"
PATH="$thm_saved_path"
assert_eq "$thm_out" "" "themes: no gsettings, no output and no error"

DOCTOR_THEME_HOME="$thm_saved_home"
DOCTOR_THEME_SHARE="$thm_saved_share"
[ -n "$thm_saved_home" ] || unset DOCTOR_THEME_HOME
[ -n "$thm_saved_share" ] || unset DOCTOR_THEME_SHARE
