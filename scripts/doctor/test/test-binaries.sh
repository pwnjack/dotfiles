# Tests for scripts/doctor/checks/binaries.sh — sourced by run-tests.sh
#
# Sourced fragment, never executed directly, so it carries no shebang; the
# directive below tells shellcheck which shell to assume (SC2148).
# shellcheck shell=bash
#
# Variables are prefixed bin_ because every test file is sourced into the
# same shell as test-lib.sh, test-symlinks.sh and test-references.sh.

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/binaries.sh"

# Assigned throughout and read by the sourced check module, not by this file
# directly, which is what SC2034 would otherwise flag.
export DOCTOR_ROOT

# bin_line <file> <substring> -> the matching line, or empty
# Severity must be asserted on the finding's own line: asserting "WARN"
# against the whole report would pass even with every classification
# inverted, a real defect found reviewing the references module.
bin_line() {
    grep -F -- "$2" "$1" 2>/dev/null | head -n1
}

bin_fixture="$(make_fixture)"
mkdir -p "$bin_fixture/hypr/config/software" \
         "$bin_fixture/hypr/config/setup" \
         "$bin_fixture/options"

# bash/ls/cat/env are installed everywhere; the -absent- names are chosen to
# be implausible as real binaries.
echo "bash" > "$bin_fixture/options/terminal"
echo "absent-browser-qq" > "$bin_fixture/options/browser"

cat > "$bin_fixture/hypr/config/apptype.lua" <<'BIN_EOF'
return {
    fileManager = "ls",
    calculator = "cat",
    polkitAgent = "absent-polkit-qq",
}
BIN_EOF

cat > "$bin_fixture/hypr/config/software/keybinds.lua" <<'BIN_EOF'
hl.bind("SUPER + RETURN", hl.dsp.exec_cmd(apps.terminal))
hl.bind("SUPER + B", hl.dsp.exec_cmd(apps.browser))
hl.bind("SUPER + E", hl.dsp.exec_cmd(apps.fileManager))
hl.bind("SUPER + X", hl.dsp.exec_cmd("absent-bin-qq"))
hl.bind("SUPER + Y", hl.dsp.exec_cmd("absent-bin-qq --flag"))
hl.bind("SUPER + A", hl.dsp.exec_cmd("~/.config/scripts/thing.sh"))
hl.bind("SUPER + D", hl.dsp.exec_cmd("$HOME/.config/scripts/other.sh"))
hl.bind("SUPER + Z", hl.dsp.exec_cmd(apps.undefinedVariable))
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("SUPER + F", hl.dsp.window.fullscreen())
hl.bind("SUPER + S", hl.dsp.exec_cmd("cat -n /dev/null"))
hl.bind("SUPER + P", hl.dsp.exec_cmd("ls | absent-pipe-qq -x"))
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("env FOO=1"), { locked = true, repeating = true })
BIN_EOF

cat > "$bin_fixture/hypr/config/setup/autostart.lua" <<'BIN_EOF'
hl.exec_cmd("env")
hl.exec_cmd("absent-daemon-qq")
hl.exec_cmd(apps.polkitAgent)
hl.exec_cmd("$HOME/.config/scripts/hyprland/startup.sh")
hl.exec_cmd("$HOME/.config/scripts/hyprland/respawn.sh absent-wrapped-qq --flag")
hl.exec_cmd("$HOME/.config/scripts/hyprland/respawn.sh cat")
BIN_EOF

git -C "$bin_fixture" add -A
git -C "$bin_fixture" commit -qm "fixture"

DOCTOR_ROOT="$bin_fixture"

# --- variable resolution ------------------------------------------------
assert_eq "$(_bin_resolve_var terminal)" "bash" "\$terminal resolves from options/"
assert_eq "$(_bin_resolve_var browser)" "absent-browser-qq" "\$browser resolves from options/"
assert_eq "$(_bin_resolve_var fileManager)" "ls" "\$fileManager resolves from apptype.lua"
assert_eq "$(_bin_resolve_var calculator)" "cat" "\$calculator resolves from apptype.lua"
assert_eq "$(_bin_resolve_var polkitAgent)" "absent-polkit-qq" "\$polkitAgent resolves from apptype.lua"
assert_eq "$(_bin_resolve_var undefinedVariable)" "" "unknown variable resolves to empty"

# --- findings -----------------------------------------------------------
bin_out_file="$DOCTOR_TEST_TMP/bin-out"
doctor_reset
check_binaries > "$bin_out_file" 2>&1
bin_out="$(cat "$bin_out_file")"

assert_contains "$(bin_line "$bin_out_file" "absent-browser-qq")" "WARN" \
    "missing \$browser binary is WARN"
assert_contains "$(bin_line "$bin_out_file" "absent-bin-qq")" "WARN" \
    "missing literal keybind binary is WARN"
assert_contains "$(bin_line "$bin_out_file" "absent-daemon-qq")" "WARN" \
    "missing autostart binary is WARN"
assert_contains "$(bin_line "$bin_out_file" "absent-wrapped-qq")" "WARN" \
    "missing binary under respawn.sh is WARN"
assert_contains "$(bin_line "$bin_out_file" "absent-polkit-qq")" "WARN" \
    "missing \$polkitAgent binary is WARN"
assert_contains "$(bin_line "$bin_out_file" "undefinedVariable")" "WARN" \
    "unresolvable variable is WARN"
assert_contains "$(bin_line "$bin_out_file" "absent-pipe-qq")" "WARN" \
    "missing binary in a pipeline segment is WARN"

assert_eq "$DOCTOR_ERRORS" "0" "nothing in this module is ERROR severity"
assert_eq "$DOCTOR_NOTICES" "0" "nothing in this module is INFO severity"

# --- what must NOT be reported ------------------------------------------
assert_not_contains "$bin_out" "scripts/thing.sh" \
    "tilde path targets are left to the reference check"
assert_not_contains "$bin_out" "scripts/other.sh" \
    "\$HOME path targets are left to the reference check"
assert_not_contains "$bin_out" "killactive" "non-exec binds are not parsed as commands"
assert_not_contains "$bin_out" "fullscreen" "dispatcher-only binds are not parsed as commands"
assert_not_contains "$bin_out" "Mod" "modifier variables are never treated as binaries"
assert_not_contains "$bin_out" "'bash'" "installed \$terminal produces no finding"
assert_not_contains "$bin_out" "'cat'" "installed literal binary produces no finding"
assert_not_contains "$bin_out" "'env'" "binary shared by keybinds and autostart produces no finding"
assert_not_contains "$bin_out" "respawn.sh" "respawn.sh's own path is left to the reference check"
assert_not_contains "$bin_out" "'--flag'" "a wrapped binary's arguments are not checked as binaries"

# --- dedupe -------------------------------------------------------------
# Count finding lines only: the name also appears in that finding's fix hint.
assert_eq "$(grep -cF "'absent-bin-qq', which is not installed" "$bin_out_file")" "1" \
    "a binary bound twice is reported once"

# --- fix hints ----------------------------------------------------------
assert_contains "$bin_out" "pacman -S absent-bin-qq" \
    "missing binary hint names the package to install"
assert_contains "$bin_out" "hypr/config/apptype.lua" \
    "unresolvable variable hint points at where to define it"

# --- ok is the all-clear and nothing else -------------------------------
assert_not_contains "$bin_out" "✓" "no green tick while findings exist"

bin_clean_fixture="$(make_fixture)"
mkdir -p "$bin_clean_fixture/hypr/config/software" \
         "$bin_clean_fixture/hypr/config/setup" \
         "$bin_clean_fixture/options"
echo "bash" > "$bin_clean_fixture/options/terminal"
printf 'hl.bind("SUPER + RETURN", hl.dsp.exec_cmd(apps.terminal))\nhl.bind("SUPER + S", hl.dsp.exec_cmd("cat"))\n' \
    > "$bin_clean_fixture/hypr/config/software/keybinds.lua"
printf 'hl.exec_cmd("env")\n' > "$bin_clean_fixture/hypr/config/setup/autostart.lua"
git -C "$bin_clean_fixture" add -A
git -C "$bin_clean_fixture" commit -qm "fixture"

DOCTOR_ROOT="$bin_clean_fixture"
bin_clean_file="$DOCTOR_TEST_TMP/bin-clean"
doctor_reset
check_binaries > "$bin_clean_file" 2>&1
bin_clean_out="$(cat "$bin_clean_file")"

assert_contains "$bin_clean_out" "✓" "green tick when every binary resolves"
assert_eq "$DOCTOR_WARNINGS" "0" "clean tree produces no warnings"

# --- systemd user units named in autostart ------------------------------
# `systemctl --user start x.service` passes the binary check trivially, so the
# unit name needs its own check or a typo fails silently every login.
_bin_unit_exists() { [ "$1" = "real-unit-qq.service" ]; }

bin_unit_fixture="$(make_fixture)"
mkdir -p "$bin_unit_fixture/hypr/config/setup" "$bin_unit_fixture/hypr/config"
# $viaVar mirrors how this repo actually writes it: the unit is reached
# through an application-table reference, so the check must resolve it rather than
# skipping the token for starting with '$'.
cat > "$bin_unit_fixture/hypr/config/apptype.lua" <<'BIN_EOF'
return {
    viaVar = "bogus-via-var-qq.service",
}
BIN_EOF
cat > "$bin_unit_fixture/hypr/config/setup/autostart.lua" <<'BIN_EOF'
hl.exec_cmd("systemctl --user start real-unit-qq.service")
hl.exec_cmd("systemctl --user start bogus-unit-qq.service")
hl.exec_cmd("systemctl --user restart another-bogus-qq.service")
hl.exec_cmd("systemctl --user start " .. apps.viaVar)
hl.exec_cmd("systemctl --user daemon-reload")
hl.exec_cmd("env")
BIN_EOF
git -C "$bin_unit_fixture" add -A
git -C "$bin_unit_fixture" commit -qm "fixture"

DOCTOR_ROOT="$bin_unit_fixture"
bin_unit_file="$DOCTOR_TEST_TMP/bin-unit"
doctor_reset
check_binaries > "$bin_unit_file" 2>&1
bin_unit_out="$(cat "$bin_unit_file")"

assert_contains "$(bin_line "$bin_unit_file" "bogus-unit-qq.service")" "WARN" \
    "an unknown systemd user unit is WARN"
assert_contains "$(bin_line "$bin_unit_file" "another-bogus-qq.service")" "WARN" \
    "the restart form is checked too"
assert_contains "$(bin_line "$bin_unit_file" "bogus-via-var-qq.service")" "WARN" \
    "a unit reached through a Hyprland variable is resolved and checked"
assert_not_contains "$bin_unit_out" "real-unit-qq.service" \
    "a unit systemd knows produces no finding"
assert_not_contains "$bin_unit_out" "daemon-reload" \
    "a systemctl verb that takes no unit is not mistaken for one"
assert_not_contains "$bin_unit_out" "'systemctl'" \
    "systemctl itself is installed and produces no finding"

# Restore the real probe for anything sourced after this file.
_bin_unit_exists() {
    command -v systemctl >/dev/null 2>&1 || return 0
    systemctl --user cat "$1" >/dev/null 2>&1
}

# --- installed package that ships no PATH executable --------------------
# Real case: hyprpolkitagent installs only /usr/lib/hyprpolkitagent/… and a
# systemd unit, so `exec-once = hyprpolkitagent` fails silently every login.
# The package lookup is stubbed because the true answer is machine-specific.
_bin_package_installed() { [ "$1" = "absent-bin-qq" ]; }

DOCTOR_ROOT="$bin_fixture"
bin_pkg_file="$DOCTOR_TEST_TMP/bin-pkg"
doctor_reset
check_binaries > "$bin_pkg_file" 2>&1

assert_contains "$(bin_line "$bin_pkg_file" "absent-bin-qq")" "ships no executable on PATH" \
    "installed package with no PATH binary gets the accurate diagnosis"
assert_contains "$(bin_line "$bin_pkg_file" "absent-bin-qq")" "silently does nothing" \
    "diagnosis states the consequence, not just the symptom"
assert_contains "$(bin_line "$bin_pkg_file" "absent-daemon-qq")" "not installed" \
    "genuinely absent package still gets the install diagnosis"
assert_not_contains "$(bin_line "$bin_pkg_file" "absent-bin-qq")" "pacman -S" \
    "no install hint for something already installed"

# Restore the real lookup for anything sourced after this file.
_bin_package_installed() {
    command -v pacman >/dev/null 2>&1 || return 1
    pacman -Q "$1" >/dev/null 2>&1
}

# --- missing config files are not an error ------------------------------
bin_empty_fixture="$(make_fixture)"
git -C "$bin_empty_fixture" commit -q --allow-empty -m "empty"
DOCTOR_ROOT="$bin_empty_fixture"
bin_empty_file="$DOCTOR_TEST_TMP/bin-empty"
doctor_reset
check_binaries > "$bin_empty_file" 2>&1
assert_eq "$DOCTOR_ERRORS$DOCTOR_WARNINGS" "00" \
    "absent keybinds/autostart files produce no findings"

# --- capture helper capability ------------------------------------------
bin_real_kms_path=$(declare -f _bin_kms_path)
bin_real_capability=$(declare -f _bin_capability)
# The helper's name comes from record.sh; the path and getcap are stubbed,
# since the real answers depend on the machine running the suite.
DOCTOR_ROOT="$bin_fixture"
mkdir -p "$bin_fixture/scripts/capture"
echo 'readonly KMS_SERVER=gsr-kms-server' > "$bin_fixture/scripts/capture/record.sh"
_bin_kms_path() { [ "$1" = gsr-kms-server ] && echo /usr/bin/gsr-kms-server; }

_bin_capability() { echo "/usr/bin/gsr-kms-server cap_net_raw=ep"; }
doctor_reset
check_binaries > "$bin_out_file" 2>&1
assert_contains "$(bin_line "$bin_out_file" "cap_sys_admin")" "WARN" \
    "helper without cap_sys_admin is WARN"
assert_contains "$(bin_line "$bin_out_file" "setcap")" "/usr/bin/gsr-kms-server" \
    "the hint names the helper's path"

_bin_capability() { echo "/usr/bin/gsr-kms-server cap_sys_admin=ep"; }
doctor_reset
check_binaries > "$bin_out_file" 2>&1
assert_eq "$(bin_line "$bin_out_file" "cap_sys_admin")" "" "helper with cap_sys_admin: no finding"

_bin_capability() { return 1; }   # getcap absent
doctor_reset
check_binaries > "$bin_out_file" 2>&1
assert_eq "$(bin_line "$bin_out_file" "cap_sys_admin")" "" "no getcap: no finding"

_bin_kms_path() { :; }             # recorder not installed
_bin_capability() { echo ""; }
doctor_reset
check_binaries > "$bin_out_file" 2>&1
assert_eq "$(bin_line "$bin_out_file" "cap_sys_admin")" "" "helper not installed: no finding"

# Restore the real probes for anything sourced after this file.
eval "$bin_real_kms_path"
eval "$bin_real_capability"

# The extraction in binaries.sh must find a name in the real record.sh, or the
# check silently turns itself off while the fixture-based cases stay green.
bin_real_name=$(sed -n 's/^readonly KMS_SERVER=\([A-Za-z0-9_.-]*\)$/\1/p' "$REPO_DIR/scripts/capture/record.sh")
assert_eq "$bin_real_name" "gsr-kms-server" "the helper name is extractable from the real record.sh"
