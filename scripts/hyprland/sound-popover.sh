#!/bin/bash
# Click on Waybar's volume icon: toggle the sound popover. Nothing of it runs
# while it is closed.
set -euo pipefail
[[ $# -eq 0 ]] || { echo 'Usage: sound-popover.sh' >&2; exit 2; }
# shellcheck source=scripts/lib/qs-launch.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/qs-launch.sh"
qs_launch sound sound Sound 'the sound popover'
if qs_ipc toggle >/dev/null 2>&1; then exit 0; fi
qs_theme SOUND
qs_anchor SOUND
qs_start
