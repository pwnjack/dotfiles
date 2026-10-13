#!/bin/bash
# The tracked hypridle.conf with and without a state file, parsed by hypridle
# itself (hyprlang 0.6 noerror + source). Needs a Wayland session; skips without.
set -euo pipefail
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/assert.sh"
conf="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/hypr/hypridle.conf"
if ! command -v hypridle >/dev/null || [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "  skip hypridle parse (no hypridle or no Wayland session)"
    exit 0
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Two seconds is far below every timeout, so no listener can fire.
rules() { HOME="$tmp" timeout 2 hypridle -v -c "$conf" 2>&1 | sed -n 's/.*Registered timeout rule for \([0-9]*\)s.*/\1/p' | sort -n | tr '\n' ' '; }

assert_eq "$(rules)" "1800 3600 " "no state file: the tracked defaults"
mkdir -p "$tmp/.local/state/hypr"
printf '$lock_timeout = 900\n\n\n# Suspend after inactivity\nlistener {\n    timeout = 7200\n    on-timeout = systemctl suspend\n}\n' > "$tmp/.local/state/hypr/hypridle.conf"
assert_eq "$(rules)" "900 3600 7200 " "the state file redefines a timeout and adds suspend"
test_summary hypridle-state
