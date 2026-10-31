#!/bin/bash
# Super+Ctrl+W: toggle the wallpaper carousel, or Waypaper without Quickshell.
set -euo pipefail
[[ $# -eq 0 ]] || { echo 'Usage: wallpaper-carousel.sh' >&2; exit 2; }
if ! command -v qs >/dev/null 2>&1 && command -v waypaper >/dev/null 2>&1; then
    exec waypaper
fi
# shellcheck source=scripts/lib/qs-launch.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/qs-launch.sh"
qs_launch wallpaper-carousel carousel Wallpaper 'the wallpaper carousel'
if qs_ipc toggle >/dev/null 2>&1; then exit 0; fi
qs_start
