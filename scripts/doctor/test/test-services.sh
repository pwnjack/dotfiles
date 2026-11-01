# Tests for scripts/doctor/checks/services.sh — sourced by run-tests.sh
#
# Sourced fragment, never executed directly, so it carries no shebang; the
# directive below tells shellcheck which shell to assume (SC2148).
# shellcheck shell=bash
#
# Variables are prefixed svc_ because every test file is sourced into the
# same shell as every other test-*.sh file.

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/services.sh"

# Assigned throughout and read by the sourced check module, not by this file
# directly, which is what SC2034 would otherwise flag.
export DOCTOR_ROOT DOCTOR_DBUS_SERVICES

# svc_line <file> <substring> -> the matching line, or empty
# Severity must be asserted on the finding's own line: asserting "WARN"
# against the whole report would pass even with every classification
# inverted, the same defect test-binaries.sh guards against.
svc_line() {
    grep -F -- "$2" "$1" 2>/dev/null | head -n1
}

# --- fixture: autostart with bare binaries, path entries, and a variable ---
svc_fixture="$(make_fixture)"
mkdir -p "$svc_fixture/hypr/config/setup" "$svc_fixture/mako" "$svc_fixture/swaync"
echo "tracked" > "$svc_fixture/mako/config"
echo "tracked" > "$svc_fixture/swaync/config"

cat > "$svc_fixture/hypr/config/setup/autostart.lua" <<'SVC_EOF'
hl.exec_cmd("svc-running-qq")
hl.exec_cmd("svc-down-qq")
hl.exec_cmd("~/.config/scripts/thing.sh")
hl.exec_cmd("$HOME/.config/scripts/other.sh")
hl.exec_cmd("systemctl --user start " .. apps.polkitAgent)
hl.exec_cmd("svc-running-qq")
hl.exec_cmd("$HOME/.config/scripts/hyprland/respawn.sh svc-wrapped-qq --flag")
hl.exec_cmd("$HOME/.config/scripts/hyprland/respawn.sh svc-wrapped-ok-qq")
SVC_EOF

cat > "$svc_fixture/install.sh" <<'SVC_EOF'
PACKAGES=(
    # comment line
    "svc-present-pkg-qq" "svc-absent-pkg-qq"
)

AUR_PACKAGES=(
    "svc-aur-present-qq"
)
SVC_EOF

git -C "$svc_fixture" add -A
git -C "$svc_fixture" commit -qm "fixture"

# --- _svc_autostart_daemons: bare binaries only, deduped ------------------
DOCTOR_ROOT="$svc_fixture"
svc_daemons="$(_svc_autostart_daemons)"
assert_contains "$svc_daemons" "svc-running-qq" "bare binary is a daemon candidate"
assert_contains "$svc_daemons" "svc-down-qq" "bare binary with trailing & is a daemon candidate"
assert_not_contains "$svc_daemons" "thing.sh" "tilde path entries are excluded from the daemon list"
assert_not_contains "$svc_daemons" "other.sh" "\$HOME path entries are excluded from the daemon list"
assert_not_contains "$svc_daemons" "polkitAgent" "bare \$variable entries are excluded from the daemon list"
assert_eq "$(printf '%s\n' "$svc_daemons" | grep -c '^svc-running-qq$')" "1" \
    "a daemon declared twice is listed once"
assert_eq "$(printf '%s\n' "$svc_daemons" | grep -c '^svc-wrapped-qq$')" "1" \
    "a daemon under respawn.sh is listed by its own name"
assert_not_contains "$svc_daemons" "respawn.sh" "respawn.sh itself is not a daemon candidate"
assert_not_contains "$svc_daemons" "--flag" "a wrapped daemon's arguments are not daemon candidates"

# --- _svc_install_packages: both arrays, comments and quotes stripped -----
svc_pkgs="$(_svc_install_packages)"
assert_contains "$svc_pkgs" "svc-present-pkg-qq" "PACKAGES entry is parsed"
assert_contains "$svc_pkgs" "svc-absent-pkg-qq" "second PACKAGES entry on the same line is parsed"
assert_contains "$svc_pkgs" "svc-aur-present-qq" "AUR_PACKAGES entry is parsed"
assert_not_contains "$svc_pkgs" "comment line" "comment lines inside the array are stripped"

# --- stub the host probes for deterministic findings ----------------------
_svc_is_running() { [ "$1" = "svc-running-qq" ]; }
_svc_package_installed() {
    case "$1" in
        svc-present-pkg-qq|svc-aur-present-qq|swaync) return 0 ;;
        mako) return 0 ;;
        *) return 1 ;;
    esac
}
_svc_bus_owner() { printf 'swaync'; }
# Never the real systemctl: only the wrapped daemon and the bare one are "failed".
_svc_unit_failed() { case "$1" in svc-wrapped-qq.service|svc-down-qq.service) return 0 ;; *) return 1 ;; esac; }
# Providers are stubbed so the orphan finding does not depend on which
# notification daemons this particular host happens to have installed.
_svc_role_providers() { printf 'swaync\nmako\n'; }

svc_out_file="$DOCTOR_TEST_TMP/services-out"
doctor_reset
check_services > "$svc_out_file" 2>&1
svc_out="$(cat "$svc_out_file")"

assert_contains "$(svc_line "$svc_out_file" "svc-down-qq")" "WARN" \
    "a declared daemon that is not running is WARN"
assert_not_contains "$svc_out" "svc-running-qq' is declared" \
    "a running daemon produces no finding"

assert_contains "$(svc_line "$svc_out_file" "svc-absent-pkg-qq")" "INFO" \
    "a package listed in install.sh but not installed is INFO"
assert_not_contains "$svc_out" "svc-present-pkg-qq' but it is not installed" \
    "an installed package produces no drift finding"
assert_not_contains "$svc_out" "svc-aur-present-qq' but it is not installed" \
    "an installed AUR package produces no drift finding"

assert_contains "$(svc_line "$svc_out_file" "org.freedesktop.Notifications")" "INFO" \
    "the D-Bus owner is reported at INFO"
assert_contains "$svc_out" "owned by 'swaync'" "the report names the actual owner"

assert_contains "$(svc_line "$svc_out_file" "'mako' is installed")" "INFO" \
    "mako installed + tracked config + not the bus owner is INFO"
assert_not_contains "$svc_out" "'swaync' is installed with a tracked config" \
    "the bus owner itself is never reported as orphaned"

assert_contains "$(svc_line "$svc_out_file" "'svc-wrapped-qq' runs under respawn.sh")" "WARN" \
    "a failed unit of a respawn.sh daemon is WARN"
assert_eq "$(grep -cF "'svc-wrapped-qq' runs under respawn.sh" "$svc_out_file")" "1" \
    "a failed wrapped unit warns once"
assert_not_contains "$svc_out" "'svc-wrapped-ok-qq' runs under respawn.sh" \
    "a wrapped daemon whose unit is not failed is silent"
assert_not_contains "$svc_out" "'svc-down-qq' runs under respawn.sh" \
    "a bare autostart daemon is not probed for a failed unit"
assert_contains "$svc_out" "svc-wrapped-qq.service" "the hint names the unit"

assert_eq "$DOCTOR_ERRORS" "0" "nothing in this module is ERROR severity"
assert_not_contains "$svc_out" "✓" "no green tick while findings exist"

# --- clean fixture: everything running, installed, and unambiguous -------
svc_clean="$(make_fixture)"
mkdir -p "$svc_clean/hypr/config/setup"
printf 'hl.exec_cmd("svc-running-qq")\n' > "$svc_clean/hypr/config/setup/autostart.lua"
printf 'PACKAGES=(\n    "svc-present-pkg-qq"\n)\n' > "$svc_clean/install.sh"
git -C "$svc_clean" add -A
git -C "$svc_clean" commit -qm "fixture"

DOCTOR_ROOT="$svc_clean"
_svc_is_running() { [ "$1" = "svc-running-qq" ]; }
_svc_package_installed() { [ "$1" = "svc-present-pkg-qq" ]; }
_svc_bus_owner() { return 1; }
_svc_role_providers() { return 0; }
_svc_unit_failed() { return 1; }

svc_clean_file="$DOCTOR_TEST_TMP/services-clean"
doctor_reset
check_services > "$svc_clean_file" 2>&1
svc_clean_out="$(cat "$svc_clean_file")"

assert_contains "$svc_clean_out" "✓" "green tick when nothing is wrong"
assert_eq "$DOCTOR_WARNINGS$DOCTOR_NOTICES" "00" "clean tree produces no findings at all"

# --- graceful degradation: pacman and busctl both unavailable ------------
DOCTOR_ROOT="$svc_fixture"
_svc_is_running() { [ "$1" = "svc-running-qq" ]; }

svc_degraded_file="$DOCTOR_TEST_TMP/services-degraded"
doctor_reset
(
    # A PATH with no pacman/busctl on it, but still holding every other
    # coreutil the module and the harness need (sed, awk, grep, sort, git...).
    svc_shim_dir="$DOCTOR_TEST_TMP/svc-shim"
    mkdir -p "$svc_shim_dir"
    for svc_tool in sh bash sed awk grep sort git tr head cat printf mkdir; do
        svc_real="$(command -v "$svc_tool" 2>/dev/null)" || continue
        ln -sf "$svc_real" "$svc_shim_dir/$svc_tool"
    done
    PATH="$svc_shim_dir"
    export PATH
    check_services > "$svc_degraded_file" 2>&1
)
svc_degraded_out="$(cat "$svc_degraded_file")"

assert_contains "$(svc_line "$svc_degraded_file" "svc-down-qq")" "WARN" \
    "daemon-running check still works without pacman/busctl on PATH"
assert_not_contains "$svc_degraded_out" "install.sh lists" \
    "package drift check produces nothing when pacman is unavailable, not a false finding per package"
assert_not_contains "$svc_degraded_out" "org.freedesktop.Notifications" \
    "D-Bus ownership check produces nothing when busctl is unavailable"
assert_not_contains "$svc_degraded_out" "is installed with a tracked config" \
    "orphan-config check produces nothing when its dependencies are unavailable"
assert_eq "$DOCTOR_ERRORS" "0" "an unavailable pacman/busctl is degraded, not an error"

# Restore the real probes for anything sourced after this file.
_svc_unit_failed() {
    command -v systemctl >/dev/null 2>&1 || return 1
    systemctl --user is-failed --quiet "$1" 2>/dev/null
}
_svc_is_running() {
    command -v pgrep >/dev/null 2>&1 || return 1
    pgrep -x "$1" >/dev/null 2>&1
}
_svc_package_installed() {
    command -v pacman >/dev/null 2>&1 || return 1
    pacman -Q "$1" >/dev/null 2>&1
}
_svc_bus_owner() {
    command -v busctl >/dev/null 2>&1 || return 1
    busctl --user list 2>/dev/null | awk -v n="$1" '$1 == n { print $3; found=1 } END { exit !found }'
}
_svc_role_providers() {
    local file pkg
    command -v pacman >/dev/null 2>&1 || return 0
    while read -r file; do
        [ -n "$file" ] || continue
        pkg="$(pacman -Qoq "$file" 2>/dev/null)"
        [ -n "$pkg" ] || continue
        printf '%s\n' "$pkg"
    done < <(_svc_role_service_files "$1")
}

# --- role providers are derived from D-Bus activation files ---------------
# The scanning half is tested against a fixture directory; the pacman lookup
# that maps a file to its package is host-specific and stubbed above.
svc_dbus_dir="$DOCTOR_TEST_TMP/dbus-services"
mkdir -p "$svc_dbus_dir"
printf '[D-BUS Service]\nName=org.freedesktop.Notifications\nExec=/usr/bin/one\n' \
    > "$svc_dbus_dir/one.service"
printf '[D-BUS Service]\nName=org.freedesktop.Notifications\nExec=/usr/bin/two\n' \
    > "$svc_dbus_dir/two.service"
printf '[D-BUS Service]\nName=org.example.Unrelated\nExec=/usr/bin/three\n' \
    > "$svc_dbus_dir/three.service"
printf '[D-BUS Service]\nName=org.freedesktop.NotificationsExtra\nExec=/usr/bin/four\n' \
    > "$svc_dbus_dir/four.service"

DOCTOR_DBUS_SERVICES="$svc_dbus_dir"
svc_found="$(_svc_role_service_files "org.freedesktop.Notifications" | sed 's|.*/||' | sort | tr '\n' ' ')"
assert_eq "$svc_found" "one.service two.service " \
    "activation files declaring the bus name are found"
assert_not_contains "$svc_found" "three.service" \
    "a file declaring an unrelated bus name is not matched"
assert_not_contains "$svc_found" "four.service" \
    "the name match is exact, not a prefix"

DOCTOR_DBUS_SERVICES="$DOCTOR_TEST_TMP/no-such-dbus-dir"
assert_eq "$(_svc_role_service_files "org.freedesktop.Notifications")" "" \
    "a missing D-Bus services directory yields nothing, not an error"

DOCTOR_DBUS_SERVICES="/usr/share/dbus-1/services"

# --- missing config files are not an error --------------------------------
svc_empty_fixture="$(make_fixture)"
git -C "$svc_empty_fixture" commit -q --allow-empty -m "empty"
DOCTOR_ROOT="$svc_empty_fixture"
svc_empty_file="$DOCTOR_TEST_TMP/services-empty"
doctor_reset
check_services > "$svc_empty_file" 2>&1
assert_eq "$DOCTOR_ERRORS$DOCTOR_WARNINGS" "00" \
    "absent autostart.lua/install.sh produce no findings"
