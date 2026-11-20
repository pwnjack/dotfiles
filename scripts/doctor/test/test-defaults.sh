# Tests for scripts/doctor/checks/defaults.sh — sourced by run-tests.sh
# shellcheck shell=bash

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/defaults.sh"

def_root="$DOCTOR_TEST_TMP/defaults"
mkdir -p "$def_root/repo/hypr/config/setup" "$def_root/repo/options" "$def_root/repo/scripts/settings" \
    "$def_root/user/kde" "$def_root/user/wine/Programs" "$def_root/system" "$def_root/bin" "$def_root/xte"
cat > "$def_root/repo/hypr/config/apptype.lua" <<'EOF'
return {
    browser = read_option("browser", "firefox"),
    terminal = read_option("terminal", "ghostty"),
    editor = read_option("editor", "nvim"), -- TUI editor
}
EOF
cat > "$def_root/repo/hypr/config/setup/envvars.lua" <<'EOF'
return function(apps)
    hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
    hl.env("BROWSER", apps.browser, true)
    hl.env("TERMINAL", apps.terminal, true)
    hl.env("EDITOR", apps.editor, true)
    -- hl.env("VISUAL", apps.nothing, true) is a comment, not a line
end
EOF
printf 'marker="# Written by terminal.sh"\n' > "$def_root/repo/scripts/settings/terminal.sh"
printf 'zen-browser\n' > "$def_root/repo/options/browser"
printf 'ghostty\n' > "$def_root/repo/options/terminal"
: > "$def_root/repo/options/editor"   # empty: apptype.lua's fallback, nvim

# Fake programs: the probes resolve these names and nothing else.
for def_bin in zen-browser ghostty alacritty nvim vlc xdg-terminal-exec; do
    printf '#!/bin/sh\n' > "$def_root/bin/$def_bin"
    chmod +x "$def_root/bin/$def_bin"
done
doctor_have() { case "$1" in /*) [ -x "$1" ] ;; *) [ -n "$1" ] && [ -x "$def_root/bin/$1" ] ;; esac; }
_def_resolve() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s\n' "$def_root/bin/$1" ;; esac; }
_def_path() { _def_resolve "$1"; }
_def_desktops() { echo hyprland; }

def_entry() {   # def_entry <dir> <path under it> <exec> [tryexec]
    printf '[Desktop Entry]\nType=Application\nExec=%s\n%s' "$3" "${4:+TryExec=$4
}" > "$def_root/$1/$2"
}
def_entry user vlc.desktop "vlc --started-from-file %U"
def_entry user thunderbird-old.desktop "/usr/lib/thunderbird-gone/thunderbird %u"
def_entry user tried.desktop "vlc %U" "missing-try"
def_entry user ghostty.desktop "$def_root/bin/ghostty --gtk-single-instance=true"
def_entry user alacritty.desktop "alacritty"
def_entry user kde/org.kde.gone.desktop "kde-gone-binary"
def_entry user wine/Programs/Gone.desktop "wine-gone-binary"
def_entry system packaged-gone.desktop "packaged-gone-binary"
printf '[Desktop Entry]\nExec=hidden-gone-binary\nHidden=true\n' > "$def_root/user/hidden-gone.desktop"
printf '[Desktop Entry]\nExec=removed-gone-binary\n' > "$def_root/user/removed-gone.desktop"
cat > "$def_root/repo/mimeapps.list" <<'EOF'
[Default Applications]
video/mp4=vlc.desktop
x-scheme-handler/mailto=thunderbird-old.desktop
text/calendar=thunderbird-old.desktop
image/png=never-installed.desktop
text/x-foo=kde-org.kde.gone.desktop
text/x-bar=wine-Programs-Gone.desktop
text/x-baz=packaged-gone.desktop
text/x-qux=hidden-gone.desktop

[Added Associations]
audio/mpeg=vlc.desktop;tried.desktop;

[Removed Associations]
video/webm=removed-gone.desktop
EOF

# Read by the sourced check module, which shellcheck cannot see from here.
# shellcheck disable=SC2034
DOCTOR_ROOT="$def_root/repo"
# shellcheck disable=SC2034
DOCTOR_APPS_DIRS="$def_root/user:$def_root/system"
# shellcheck disable=SC2034
DOCTOR_XTE_CONFIG="$def_root/xte"

# Shell: a stale value naming a missing program, a stale but installed one, and
# an unset one. systemd, in its own $'...' quoting: a missing program, a stale
# but installed value (not a notice: only the shell's is), and a list.
_def_env() { case "$1" in BROWSER) echo firefox ;; TERMINAL) echo alacritty ;; esac; }
_def_systemd_raw() {
    printf '%s\n' "HOME=/home/x" "EDITOR=\$'gone-editor --flag \\'x\\''" "TERMINAL=alacritty" \
        "BROWSER=zen-browser:firefox"
}
_def_xte_path() { printf '%s\n' "$def_root/user/alacritty.desktop"; }

run_check check_defaults
# firefox, gone-editor, xdg-terminal-exec -> alacritty, thunderbird-old, tried,
# kde gone, wine gone, packaged gone
assert_eq "$DOCTOR_WARNINGS" "8" "defaults: eight warnings"
assert_eq "$DOCTOR_NOTICES" "1" "defaults: one notice"
assert_contains "$CHECK_OUT" "BROWSER is firefox in this shell, and firefox is not installed" "defaults: a stale export naming a missing program warns"
assert_contains "$CHECK_OUT" "EDITOR is gone-editor --flag 'x' for systemd" "defaults: systemd's \$'...' quoting is undone"
assert_contains "$CHECK_OUT" "TERMINAL is alacritty in this shell, but options/ says ghostty" "defaults: a stale but installed shell value is a notice"
assert_not_contains "$CHECK_OUT" "TERMINAL is alacritty for systemd" "defaults: a stale but installed systemd value is not reported"
assert_not_contains "$CHECK_OUT" "BROWSER is zen-browser:firefox" "defaults: only the first of BROWSER's colon-separated list is checked"
assert_contains "$CHECK_OUT" "xdg-terminal-exec opens alacritty.desktop, not options/terminal (ghostty)" "defaults: xdg-terminal-exec must open options/terminal"
assert_contains "$CHECK_OUT" "scripts/settings/terminal.sh" "defaults: the terminal fix runs terminal.sh"
assert_contains "$CHECK_OUT" "thunderbird-old.desktop, which runs /usr/lib/thunderbird-gone/thunderbird" "defaults: an association with a dead program warns"
assert_contains "$CHECK_OUT" "tried.desktop, which runs missing-try" "defaults: Added Associations and TryExec are checked"
assert_contains "$CHECK_OUT" "kde-org.kde.gone.desktop" "defaults: an ID's dash finds an entry in a subdirectory"
assert_contains "$CHECK_OUT" "wine-Programs-Gone.desktop" "defaults: an ID's dashes find an entry two directories down"
assert_eq "$(grep -c 'WARN.*thunderbird-old' "$DOCTOR_TEST_TMP/check.out")" "1" "defaults: one warning per entry, not per type"
assert_contains "$(grep -A1 'thunderbird-old' "$DOCTOR_TEST_TMP/check.out")" "rm " "defaults: a per-user entry may be removed"
assert_not_contains "$(grep -A1 'packaged-gone' "$DOCTOR_TEST_TMP/check.out")" "rm " "defaults: a packaged entry is never offered for rm"
assert_not_contains "$CHECK_OUT" "never-installed" "defaults: an app this machine never had is skipped"
assert_not_contains "$CHECK_OUT" "hidden-gone" "defaults: a Hidden (deleted) entry is skipped"
assert_not_contains "$CHECK_OUT" "removed-gone" "defaults: Removed Associations are not checked"
assert_not_contains "$CHECK_OUT" "VISUAL" "defaults: commented hl.env lines are ignored"
assert_eq "$(grep -c 'EDITOR is' "$DOCTOR_TEST_TMP/check.out")" "1" "defaults: an unset shell value is not reported, only systemd's"
assert_not_contains "$CHECK_OUT" "✓" "defaults: no all-clear with findings"

# Everything right: the all-clear, and the fallback when an option file is empty.
_def_env() { case "$1" in BROWSER) echo zen-browser ;; TERMINAL) echo "A=\"x y\" B='p q' C=1 ghostty" ;; EDITOR) echo "LANG=C nvim" ;; esac; }
_def_systemd_raw() { printf '%s\n' "EDITOR=\$'nvim --clean'" "BROWSER=ONLY=1"; }
_def_xte_path() { printf '%s\n' "$def_root/user/ghostty.desktop"; }
printf '[Default Applications]\nvideo/mp4=vlc.desktop\n' > "$def_root/repo/mimeapps.list"
run_check check_defaults
assert_eq "$DOCTOR_WARNINGS" "0" "defaults: quoted systemd values, quoted VAR= prefixes and a bare assignment pass"
assert_eq "$DOCTOR_NOTICES" "2" "defaults: the shell's differing EDITOR and TERMINAL are notices"
printf 'LANG=C nvim\n' > "$def_root/repo/options/editor"
_def_env() { case "$1" in BROWSER) echo zen-browser ;; TERMINAL) echo ghostty ;; EDITOR) echo "LANG=C nvim" ;; esac; }
run_check check_defaults
assert_eq "$((DOCTOR_WARNINGS + DOCTOR_NOTICES))" "0" "defaults: matching values are clean"
assert_contains "$CHECK_OUT" "✓" "defaults: clean prints the all-clear"
: > "$def_root/repo/options/editor"

# The options/ value itself naming a missing program is check_binaries' finding.
_def_env() { case "$1" in BROWSER) echo zen-browser ;; esac; }
_def_systemd_raw() { :; }
rm -f "$def_root/bin/zen-browser"
run_check check_defaults
assert_eq "$((DOCTOR_WARNINGS + DOCTOR_NOTICES))" "0" "defaults: a missing options/ program is left to check_binaries"
printf '#!/bin/sh\n' > "$def_root/bin/zen-browser"
chmod +x "$def_root/bin/zen-browser"

# A hand-written list, then a desktop-specific one, stop terminal.sh fixing it:
# the hint names the file instead.
_def_xte_path() { printf '%s\n' "$def_root/user/alacritty.desktop"; }
printf 'alacritty.desktop\n' > "$def_root/xte/xdg-terminals.list"
run_check check_defaults
assert_contains "$CHECK_OUT" "written by hand" "defaults: a hand-written list is named in the hint"
printf 'alacritty.desktop\n' > "$def_root/xte/hyprland-xdg-terminals.list"
run_check check_defaults
assert_contains "$CHECK_OUT" "hyprland-xdg-terminals.list, which takes precedence" "defaults: a desktop-specific list is named in the hint"
rm -f "$def_root/xte/"*.list
printf '# Written by terminal.sh\nalacritty.desktop\n' > "$def_root/xte/xdg-terminals.list"
run_check check_defaults
assert_contains "$CHECK_OUT" "fix: bash " "defaults: terminal.sh's own list gets the terminal.sh hint"
rm -f "$def_root/xte/"*.list

# A broken xdg-terminal-exec (the stub that ran "$TERMINAL -e" unset).
_def_xte_path() { :; }
run_check check_defaults
assert_eq "$DOCTOR_WARNINGS" "1" "defaults: a broken xdg-terminal-exec warns"
assert_contains "$CHECK_OUT" "does not work" "defaults: says xdg-terminal-exec does not work"

# Not installed at all: install.sh's package drift reports that, not this check.
doctor_have() { case "$1" in xdg-terminal-exec) return 1 ;; /*) [ -x "$1" ] ;; *) [ -n "$1" ] && [ -x "$def_root/bin/$1" ] ;; esac; }
run_check check_defaults
assert_eq "$((DOCTOR_WARNINGS + DOCTOR_NOTICES))" "0" "defaults: a missing xdg-terminal-exec is left to package drift"

# The real systemd decoding, on the probe's own output format.
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/defaults.sh"
_def_systemd_raw() { printf '%s\n' "MANPAGER=\$'sh -c \\'col -bx | bat\\''" "PAGER=less"; }
assert_eq "$(_def_systemd_env MANPAGER)" "sh -c 'col -bx | bat'" "defaults: \$'...' with escaped quotes decodes"
assert_eq "$(_def_systemd_env PAGER)" "less" "defaults: a plain value passes through"

# Reset for later files: the stubs above replaced the host probes.
unset -f def_entry
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/defaults.sh"
# shellcheck disable=SC2034
DOCTOR_APPS_DIRS="" DOCTOR_XTE_CONFIG=""
