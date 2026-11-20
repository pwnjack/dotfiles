#!/bin/bash
#
# Tests for scripts/settings/terminal.sh against fake terminals and fake
# desktop entries. Nothing touches the real ~/.config or data directories.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/terminal.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

mkdir -p "$TMP/bin" "$TMP/config/options" "$TMP/home/applications" "$TMP/data/applications/kde"
for t in ghostty alacritty konsole bare kitty; do
    printf '#!/bin/sh\n' > "$TMP/bin/$t"
done
chmod +x "$TMP/bin/"*

entry() {   # entry <path under data> <exec> [categories]
    printf '[Desktop Entry]\nType=Application\nName=X\nExec=%s\nCategories=%s\n' \
        "$2" "${3:-System;TerminalEmulator;}" > "$TMP/data/applications/$1"
}
entry com.mitchellh.ghostty.desktop "$TMP/bin/ghostty --gtk-single-instance=true"
entry Alacritty.desktop "alacritty"
entry kde/org.kde.konsole.desktop "konsole"
entry ghostty-editor.desktop "ghostty -e nvim" "Utility;TextEditor;"
# A hidden decoy that sorts first: it must be skipped, not chosen.
printf '[Desktop Entry]\nType=Application\nExec=alacritty\nCategories=TerminalEmulator;\nHidden=true\n' \
    > "$TMP/data/applications/0-hidden-alacritty.desktop"
# An [Desktop Action] Exec must not stand in for the entry's own Exec.
printf '[Desktop Entry]\nType=Application\nExec=bare\nCategories=TerminalEmulator;\n[Desktop Action new]\nExec=konsole\n' \
    > "$TMP/data/applications/bare.desktop"

# kitty's helper sorts first in C order: hidden, and a file opener, it must
# never be the terminal (it would read the command as URLs to open).
printf '[Desktop Entry]\nType=Application\nExec=kitty +open %%U\nCategories=TerminalEmulator;\nNoDisplay=true\n' \
    > "$TMP/data/applications/kitty-open.desktop"
printf '[Desktop Entry]\nType=Application\nExec=kitty --single %%F\nCategories=TerminalEmulator;\n' \
    > "$TMP/data/applications/kitty-files.desktop"
printf '[Desktop Entry]\nType=Application\nExec=kitty\nCategories=TerminalEmulator;\nNoDisplay=true\n' \
    > "$TMP/data/applications/kitty-hidden.desktop"
entry kitty.desktop "kitty"
entry kitty-z.desktop "kitty"

target="$TMP/config/xdg-terminals.list"
run() {
    printf '%s\n' "$1" > "$TMP/config/options/terminal"
    PATH="$TMP/bin:$PATH" XDG_CONFIG_HOME="$TMP/config" XDG_DATA_HOME="$TMP/home" \
        XDG_DATA_DIRS="$TMP/data" bash "$SCRIPT"
}
listed() { grep -v '^#' "$target" 2>/dev/null; }

run ghostty
assert_eq "$?" 0 "exits 0"
assert_eq "$(listed)" "com.mitchellh.ghostty.desktop" "ghostty's entry is chosen through its absolute Exec"
assert_contains "$(head -n 1 "$target")" "scripts/settings/terminal.sh" "the list says who wrote it"

run "alacritty --option x"
assert_eq "$(listed)" "Alacritty.desktop" "arguments are ignored, and a hidden entry is skipped"

run konsole
assert_eq "$(listed)" "kde-org.kde.konsole.desktop" "an entry in a subdirectory gets its desktop ID"

run bare
assert_eq "$(listed)" "bare.desktop" "only the [Desktop Entry] group's Exec counts"

run kitty
assert_eq "$(listed)" "kitty-z.desktop" "hidden entries and file openers are skipped; C order picks among the rest"
printf 'kitty\n' > "$TMP/config/options/terminal"
LC_ALL=en_US.UTF-8 PATH="$TMP/bin:$PATH" XDG_CONFIG_HOME="$TMP/config" XDG_DATA_HOME="$TMP/home" \
    XDG_DATA_DIRS="$TMP/data" bash "$SCRIPT" 2>/dev/null
assert_eq "$(listed)" "kitty-z.desktop" "the choice does not depend on the locale"

# A user entry with the same ID shadows the system one, even when it is not a terminal.
printf '[Desktop Entry]\nType=Application\nExec=alacritty\nCategories=Utility;\n' > "$TMP/home/applications/Alacritty.desktop"
run alacritty
assert_absent "$target" \
    "a shadowed entry does not count, and no match removes the list"
rm -f "$TMP/home/applications/Alacritty.desktop"

run missing-terminal
assert_absent "$target" "a missing binary leaves no list"

printf 'my-terminal.desktop\n' > "$target"
run ghostty
assert_eq "$(cat "$target")" "my-terminal.desktop" "a list written by hand is left alone"
rm -f "$target"

rm -f "$TMP/config/options/terminal"
PATH="$TMP/bin:$PATH" XDG_CONFIG_HOME="$TMP/config" XDG_DATA_HOME="$TMP/home" \
    XDG_DATA_DIRS="$TMP/data" bash "$SCRIPT"
assert_eq "$(listed)" "com.mitchellh.ghostty.desktop" "no option falls back to ghostty, like apptype.lua"

touch -d '2001-01-01' "$target"
run ghostty
assert_eq "$(stat -c %Y "$target")" "$(date -d '2001-01-01' +%s)" "an unchanged choice does not rewrite the list"

test_summary terminal
