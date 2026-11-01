# Tests for scripts/doctor/checks/plugins.sh — sourced by run-tests.sh
# shellcheck shell=bash

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/plugins.sh"

# The host probes are stubbed: the installed set is whatever these name.
plg_typelibs=" GLib Gio "
plg_styles=" 6:kvantum "
_plg_typelib_present() { [[ $plg_typelibs == *" $1 "* ]]; }
_plg_qt_style_present() { [[ $plg_styles == *" $1:${2,,} "* ]]; }

plg_root="$(make_fixture)"
mkdir -p "$plg_root/quickshell/panel" "$plg_root/docs" "$plg_root/scripts/doctor" \
    "$plg_root/defaults/qt5ct" "$plg_root/defaults/qt6ct" "$plg_root/qt5ct"
printf "import NM from 'gi://NM';\nimport Gio from 'gi://Gio?version=2.0';\n" > "$plg_root/quickshell/panel/nm.js"
printf "import GLib from 'gi://GLib';\n" > "$plg_root/quickshell/panel/glib.mjs"
printf "import X from 'gi://Untracked';\n" > "$plg_root/quickshell/panel/scratch.js"
printf "Example: gi://DocOnly\n" > "$plg_root/docs/notes.md"
printf "# gi://DoctorOnly\n" > "$plg_root/scripts/doctor/x.sh"
# A tracked binary holding the bytes: git grep would print "Binary file ...
# matches" in place of the match unless binaries are skipped.
printf 'PNG\0gi://BinaryOnly\0' > "$plg_root/quickshell/panel/pic.png"
printf '[Appearance]\nstyle=kvantum\n' > "$plg_root/defaults/qt5ct/qt5ct.conf"
# Spaces round the value and CRLF endings, as a hand- or Windows-edited file
# has them: the "installed Qt 6 style" assertion below fails unless both trim.
printf '[Appearance]\r\nstyle = kvantum \r\n' > "$plg_root/defaults/qt6ct/qt6ct.conf"
# The live qt5ct file overrides its default. The [Interface] style comes first
# and never counts.
printf '[Interface]\nstyle=other\n[Appearance]\nicon_theme=x\nstyle=Breeze\n' > "$plg_root/qt5ct/qt5ct.conf"
git -C "$plg_root" add quickshell/panel/nm.js quickshell/panel/glib.mjs quickshell/panel/pic.png docs scripts defaults

plg_saved_root="$DOCTOR_ROOT"
DOCTOR_ROOT="$plg_root"
doctor_reset
check_plugins > "$DOCTOR_TEST_TMP/plugins.out" 2>&1
plg_text="$(cat "$DOCTOR_TEST_TMP/plugins.out")"
assert_eq "$DOCTOR_WARNINGS" "2" "plugins: a missing typelib and a missing Qt 5 style"
assert_contains "$plg_text" "No typelib for gi://NM" "plugins: names the missing typelib"
assert_not_contains "$plg_text" "gi://Gio" "plugins: a ?version= import of an installed typelib is fine"
assert_not_contains "$plg_text" "gi://GLib" "plugins: an installed typelib is fine"
assert_not_contains "$plg_text" "Untracked" "plugins: an untracked file names no target"
assert_not_contains "$plg_text" "DocOnly" "plugins: docs/ is not scanned"
assert_not_contains "$plg_text" "DoctorOnly" "plugins: the doctor's own tree is not scanned"
assert_not_contains "$plg_text" "Binary file" "plugins: a binary file names no namespace"
assert_not_contains "$plg_text" "BinaryOnly" "plugins: binary files are not scanned"
assert_contains "$plg_text" "Qt 5 has no 'Breeze' style plugin, which qt5ct/qt5ct.conf selects" "plugins: the live file's style wins over its default"
assert_not_contains "$plg_text" "'other'" "plugins: only [Appearance] style counts"
assert_not_contains "$plg_text" "Qt 6" "plugins: an installed Qt 6 style is fine"
assert_contains "$plg_text" "qt/plugins/styles/" "plugins: the Qt 5 hint searches Qt 5's plugin directory"
assert_not_contains "$plg_text" "✓" "plugins: no all-clear with findings"

# With no live file the default's style is read, and the installed set covers
# everything, so the check says so.
rm "$plg_root/qt5ct/qt5ct.conf"
plg_typelibs=" GLib Gio NM "
plg_styles=" 5:kvantum 6:kvantum "
doctor_reset
check_plugins > "$DOCTOR_TEST_TMP/plugins.out" 2>&1
plg_text="$(cat "$DOCTOR_TEST_TMP/plugins.out")"
assert_eq "$DOCTOR_WARNINGS" "0" "plugins: nothing missing, nothing reported"
assert_contains "$plg_text" "Every imported typelib and selected Qt style plugin is installed" "plugins: all-clear when nothing is missing"

# The default alone, with Qt 5's engine missing: kvantum without kvantum-qt5.
plg_styles=" 6:kvantum "
doctor_reset
check_plugins > "$DOCTOR_TEST_TMP/plugins.out" 2>&1
plg_text="$(cat "$DOCTOR_TEST_TMP/plugins.out")"
assert_contains "$plg_text" "Qt 5 has no 'kvantum' style plugin, which defaults/qt5ct/qt5ct.conf selects" "plugins: a default's style is checked when nothing is rendered"
DOCTOR_ROOT="$plg_saved_root"

# The real probes, against fixture directories: a typelib is found on
# GI_TYPELIB_PATH by namespace and not by prefix, and Qt's built-in styles
# need no plugin.
unset -f _plg_typelib_present _plg_qt_style_present
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/plugins.sh"
mkdir -p "$DOCTOR_TEST_TMP/gi"
: > "$DOCTOR_TEST_TMP/gi/FakeNs-1.0.typelib"
plg_saved_gi="${GI_TYPELIB_PATH-}"
GI_TYPELIB_PATH="/nonexistent:$DOCTOR_TEST_TMP/gi"
_plg_typelib_present FakeNs && plg_r=found || plg_r=missing
assert_eq "$plg_r" found "plugins: the probe searches every GI_TYPELIB_PATH entry"
_plg_typelib_present Fake && plg_r=found || plg_r=missing
assert_eq "$plg_r" missing "plugins: the probe matches a whole namespace, not a prefix"
# A directory whose name holds glob characters is a literal path.
mkdir -p "$DOCTOR_TEST_TMP/gi[x]*"
: > "$DOCTOR_TEST_TMP/gi[x]*/BracketNs-1.0.typelib"
GI_TYPELIB_PATH="$DOCTOR_TEST_TMP/gi[x]*"
_plg_typelib_present BracketNs && plg_r=found || plg_r=missing
assert_eq "$plg_r" found "plugins: a GI_TYPELIB_PATH entry with [ or * is matched literally"
GI_TYPELIB_PATH="$plg_saved_gi"
plg_saved_qt="${DOCTOR_QT_LIBDIR-}"
DOCTOR_QT_LIBDIR="$DOCTOR_TEST_TMP/qt-lib"
mkdir -p "$DOCTOR_QT_LIBDIR/qt/plugins/styles" "$DOCTOR_QT_LIBDIR/qt6/plugins/styles"
: > "$DOCTOR_QT_LIBDIR/qt/plugins/styles/libQtFiveStyle.so"
: > "$DOCTOR_QT_LIBDIR/qt6/plugins/styles/libQtSixStyle.so"
_plg_qt_style_present 5 qtfivestyle && plg_r=found || plg_r=missing
assert_eq "$plg_r" found "plugins: the real Qt 5 lookup finds a plugin case-insensitively"
_plg_qt_style_present 6 qtsixstyle && plg_r=found || plg_r=missing
assert_eq "$plg_r" found "plugins: the real Qt 6 lookup finds a plugin case-insensitively"
_plg_qt_style_present 5 qtsixstyle && plg_r=found || plg_r=missing
assert_eq "$plg_r" missing "plugins: Qt 5 cannot use a Qt 6 plugin"
_plg_qt_style_present 6 qtfivestyle && plg_r=found || plg_r=missing
assert_eq "$plg_r" missing "plugins: Qt 6 cannot use a Qt 5 plugin"
_plg_qt_style_present 5 Fusion && plg_r=found || plg_r=missing
assert_eq "$plg_r" found "plugins: Fusion is built in"
_plg_qt_style_present 6 no-such-style-xyz && plg_r=found || plg_r=missing
assert_eq "$plg_r" missing "plugins: an unknown style is missing"
DOCTOR_QT_LIBDIR="$plg_saved_qt"
