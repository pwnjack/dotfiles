#!/bin/bash
# Super+H: toggle the keybindings overlay. A broken Super+H must not look like
# a dead key: the shared launcher notifies every failure.
set -euo pipefail
[[ $# -eq 0 ]] || { echo 'Usage: keybinds-overlay.sh' >&2; exit 2; }
# shellcheck source=scripts/lib/qs-launch.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/qs-launch.sh"
qs_launch keybinds-overlay keybinds Keybindings 'the keybindings overlay'
if qs_ipc toggle >/dev/null 2>&1; then exit 0; fi
qs_theme KEYBINDS
qs_start
