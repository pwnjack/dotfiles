#!/bin/bash
# The tracked hypridle.conf with and without a state file, parsed by hypridle
# itself (hyprlang 0.6 noerror + source), without connecting to a live session.
set -euo pipefail
# shellcheck disable=SC1091 # Resolved from the repository root; checked separately.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/assert.sh"
conf="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/hypr/hypridle.conf"
if ! command -v hypridle >/dev/null; then
    echo "  skip hypridle parse (no hypridle)"
    exit 0
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Configuration is parsed and registered before the Wayland connection. A
# nonexistent private socket makes the daemon exit immediately after parsing;
# the assertions still require every expected listener, including the overlay.
# A private D-Bus address also prevents any contact with the session bus.
rules() {
    { HOME="$tmp" XDG_RUNTIME_DIR="$tmp" WAYLAND_DISPLAY=unused-test-display \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$tmp/no-bus" \
        timeout 2 hypridle -v -c "$conf" 2>&1 || true; } |
        sed -n 's/.*Registered timeout rule for \([0-9]*\)s.*/\1/p' | sort -n | tr '\n' ' '
}

assert_eq "$(rules)" "1800 3600 " "no state file: the tracked defaults"
mkdir -p "$tmp/.local/state/hypr"
# shellcheck disable=SC2016 # Literal Hyprlang variable, expanded by hypridle.
printf '$lock_timeout = 900\n\n\n# Suspend after inactivity\nlistener {\n    timeout = 7200\n    on-timeout = systemctl suspend\n}\n' > "$tmp/.local/state/hypr/hypridle.conf"
assert_eq "$(rules)" "900 3600 7200 " "the state file redefines a timeout and adds suspend"
test_summary hypridle-state
