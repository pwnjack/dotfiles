#!/bin/bash
# Super+Shift+S / Super+Shift+R: open the capture strip on the Screenshot or
# Record tab. A second press of the same key closes it; the other key switches
# tab. Super+Shift+R while a recording runs (or counts down) stops it instead,
# without opening anything. The capturing is scripts/hyprland/screenshot.sh
# and scripts/capture/record.sh.
set -euo pipefail
mode="${1:-screenshot}"
case "$mode" in
    screenshot|record) ;;
    *) echo 'Usage: capture-bar.sh [screenshot|record]' >&2; exit 2 ;;
esac
# shellcheck source=scripts/lib/qs-launch.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/qs-launch.sh"
# shellcheck disable=SC2154  # config_dir is set by qs-launch.sh
record="$config_dir/scripts/capture/record.sh"
if [ "$mode" = record ] && "$record" status >/dev/null 2>&1; then
    exec "$record" stop
fi
qs_launch capture capture Capture 'the capture bar'
if qs_ipc toggle "$mode" >/dev/null 2>&1; then exit 0; fi
qs_theme CAPTURE
export CAPTURE_MODE="$mode"
qs_start
