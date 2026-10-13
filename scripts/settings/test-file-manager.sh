#!/bin/bash
#
# Tests for scripts/settings/file-manager.sh against fake file managers, fake
# D-Bus service files and a fake busctl. Nothing touches the real bus or
# ~/.local/share.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/file-manager.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

mkdir -p "$TMP/bin" "$TMP/config/options" "$TMP/data/dbus-1/services" "$TMP/home"
for fm in strata thunar nautilus dolphin yazi; do
    printf '#!/bin/sh\n' > "$TMP/bin/$fm"
done
ln -s thunar "$TMP/bin/Thunar"   # Thunar's service names the capitalised link
printf '#!/bin/sh\necho "busctl $*" >> "%s"\n' "$TMP/bus" > "$TMP/bin/busctl"
chmod +x "$TMP/bin/"*

service() {   # service <file> <exec>
    printf '[D-BUS Service]\nName=org.freedesktop.FileManager1\nExec=%s\n' "$2" \
        > "$TMP/data/dbus-1/services/$1"
}
service org.freedesktop.FileManager1.service "$TMP/bin/nautilus --gapplication-service"
service org.kde.dolphin.FileManager1.service "$TMP/bin/dolphin --daemon"
service org.xfce.Thunar.FileManager1.service "$TMP/bin/Thunar --gapplication-service"
service io.github.lgse.Strata.FileManager1.service "$TMP/bin/strata --gapplication-service"
printf '[D-BUS Service]\nName=org.example.Other\nExec=%s\n' "$TMP/bin/thunar" \
    > "$TMP/data/dbus-1/services/org.example.Other.service"

target="$TMP/home/dbus-1/services/org.freedesktop.FileManager1.service"
run() {
    printf '%s\n' "$1" > "$TMP/config/options/filemanager"
    : > "$TMP/bus"
    PATH="$TMP/bin:$PATH" HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config" XDG_DATA_HOME="$TMP/home" \
        XDG_DATA_DIRS="$TMP/data" bash "$SCRIPT"
}

run strata
assert_eq "$?" 0 "Strata exits 0"
assert_contains "$(cat "$target" 2>/dev/null)" "$TMP/bin/strata --gapplication-service" \
    "strata claims its packaged FileManager1 service"

run thunar
assert_eq "$?" 0 "exits 0"
assert_contains "$(cat "$target" 2>/dev/null)" "Thunar --gapplication-service" \
    "thunar claims the service through its own file, matched through the Thunar link"
assert_contains "$(cat "$TMP/bus")" "ReloadConfig" "a change reloads the bus"

run thunar
assert_eq "$(cat "$TMP/bus")" "" "an unchanged choice does not reload the bus"

run "dolphin --new-window"
assert_contains "$(cat "$target")" "dolphin --daemon" "arguments in the option are ignored; dolphin's file is used"

run yazi
assert_eq "$([ -e "$target" ] && echo present || echo absent)" absent \
    "a file manager without a D-Bus service leaves the system's choice"
assert_contains "$(cat "$TMP/bus")" "ReloadConfig" "removing the override reloads the bus"

run nautilus
run missing-app
assert_eq "$([ -e "$target" ] && echo present || echo absent)" absent "a missing binary removes the override"

run "  dolphin"
assert_contains "$(cat "$target")" "dolphin --daemon" "leading spaces in the option are ignored"

printf '[D-BUS Service]\nName=org.freedesktop.FileManager1\nExec=/opt/custom-fm\n' > "$target"
run yazi
assert_contains "$(cat "$target" 2>/dev/null)" "/opt/custom-fm" "an override this script did not write is left alone"
rm -f "$target"

rm -f "$TMP/config/options/filemanager"
: > "$TMP/bus"
PATH="$TMP/bin:$PATH" HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config" XDG_DATA_HOME="$TMP/home" \
    XDG_DATA_DIRS="$TMP/data" bash "$SCRIPT"
assert_contains "$(cat "$target" 2>/dev/null)" "strata --gapplication-service" "no option falls back to strata, like apptype.lua"

test_summary file-manager
