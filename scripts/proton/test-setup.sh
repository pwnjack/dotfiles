#!/bin/bash
#
# Tests for scripts/proton/setup.sh and the pacman hook it installs.
#
# pacman, systemctl, pgrep and sudo are stubs on PATH that log what they are
# asked, so nothing here touches the real system. sudo logs and runs nothing.
# cmp and stat are stubbed too, so the installed hook's state is the fixture's
# and never the real /etc/pacman.d/hooks copy on the machine running the suite.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$TEST_DIR/setup.sh"
HOOK="$TEST_DIR/proton-vpn-on-demand.hook"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/pacman" <<'STUB'
#!/bin/bash
[ "${STUB_INSTALLED:-yes}" = yes ]
STUB
cat > "$TMP/bin/systemctl" <<'STUB'
#!/bin/bash
printf 'systemctl %s\n' "$*" >> "$STUB_LOG"
case "$1" in
    is-enabled) [ "${STUB_ENABLED:-yes}" = yes ] ;;
    is-active) [ "${STUB_ACTIVE:-yes}" = yes ] ;;
    stop) [ -z "${STUB_STOP_FAIL:-}" ] ;;
    *) exit 0 ;;
esac
STUB
cat > "$TMP/bin/pgrep" <<'STUB'
#!/bin/bash
printf 'pgrep %s\n' "$*" >> "$STUB_LOG"
[ "${STUB_APP:-closed}" = open ]
STUB
cat > "$TMP/bin/cmp" <<'STUB'
#!/bin/bash
[ "${STUB_HOOK:-absent}" = current ]
STUB
cat > "$TMP/bin/stat" <<'STUB'
#!/bin/bash
[ "${STUB_HOOK:-absent}" = current ] && echo 'root:root 644'
STUB
cat > "$TMP/bin/sudo" <<'STUB'
#!/bin/bash
printf 'sudo %s\n' "$*" >> "$STUB_LOG"
[ -z "${STUB_SUDO_FAIL:-}" ]
STUB
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH" STUB_LOG="$TMP/log"

# run_setup [env...] -- sets $out, $status and $log.
run_setup() {
    : > "$STUB_LOG"
    out=$(env "$@" bash "$SETUP" 2>&1)
    status=$?
    log=$(cat "$STUB_LOG")
}

run_setup STUB_INSTALLED=no
assert_eq "$status" 0 "without proton-vpn-daemon setup succeeds"
assert_contains "$out" "nothing to do" "and says there is nothing to do"
assert_eq "$log" "" "and asks for nothing"

run_setup
assert_eq "$status" 0 "an enabled, running daemon with the app closed is handled"
assert_contains "$log" "sudo install -D -m 0644 -o root -g root $HOOK /etc/pacman.d/hooks/zz-proton-vpn-on-demand.hook" \
    "the hook is installed root-owned under pacman's hook directory"
assert_contains "$log" "sudo systemctl disable --quiet proton.VPN.service" "the unit is disabled at boot"
assert_contains "$log" "sudo systemctl stop proton.VPN.service" "the daemon is stopped"

run_setup STUB_APP=open
assert_eq "$status" 0 "with the app open setup still succeeds"
assert_contains "$log" "sudo systemctl disable --quiet proton.VPN.service" "the unit is still disabled at boot"
assert_not_contains "$log" "systemctl stop" "but the daemon is left running"
assert_contains "$out" "stays up while the Proton app is open" "and setup says so"

run_setup STUB_HOOK=current STUB_ENABLED=no STUB_ACTIVE=no
assert_eq "$status" 0 "a finished setup can run again"
assert_eq "$(grep -c '^sudo' "$STUB_LOG")" 0 "and asks for nothing through sudo"
assert_contains "$out" "Upgrade hook is already current" "setup reports the hook current"
assert_contains "$out" "already off at boot" "and the daemon off at boot"

run_setup STUB_SUDO_FAIL=1
assert_eq "$status" 1 "a refused sudo fails setup"
assert_contains "$out" "Failed to install the upgrade hook" "naming what failed"

# The hook's Exec, with its absolute paths pointed at the stubs: the unit is
# always disabled, stopped only while the app is closed, and the command exits
# 0 so pacman never reports the hook as failed.
exec_line=$(sed -n 's/^Exec = //p' "$HOOK")
assert_contains "$exec_line" "/usr/bin/sh -c '" "the hook runs one sh -c command"
hook_cmd=${exec_line#"/usr/bin/sh -c '"}
hook_cmd=${hook_cmd%"'"}
hook_cmd=${hook_cmd//\/usr\/bin\//}

run_hook() {
    : > "$STUB_LOG"
    env "$@" sh -c "$hook_cmd"
    status=$?
    log=$(cat "$STUB_LOG")
}

run_hook STUB_STOP_FAIL=1
assert_eq "$status" 0 "the hook exits 0 even when stopping fails"
run_hook
assert_contains "$log" "systemctl disable --quiet proton.VPN.service" "the hook disables the unit"
assert_contains "$log" "systemctl stop proton.VPN.service" "and stops the daemon while the app is closed"
run_hook STUB_APP=open
assert_contains "$log" "pgrep -x protonvpn-app" "the hook looks for the app by its exact name"
assert_not_contains "$log" "systemctl stop" "and leaves the daemon running while the app is open"
assert_contains "$(sed -n '/^\[Trigger\]/,/^\[Action\]/p' "$HOOK")" "Target = proton-vpn-daemon" \
    "the hook fires for proton-vpn-daemon"

test_summary proton-setup
