#!/bin/bash
# Click on Waybar's custom/media: toggle the media card. Nothing of it runs
# while it is closed.
set -euo pipefail
[[ $# -eq 0 ]] || { echo 'Usage: media-popover.sh' >&2; exit 2; }
# shellcheck source=scripts/lib/qs-launch.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/qs-launch.sh"
# shellcheck source=scripts/hyprland/medialib.sh
source "$(dirname "${BASH_SOURCE[0]}")/medialib.sh"
qs_launch media media Media 'the media card'
if qs_ipc toggle >/dev/null 2>&1; then exit 0; fi
# The card opens on the player the bar shows. With no player on the bus the
# bar shows none, and there is nothing to open.
MEDIA_PLAYER=$(media_player) || true
[[ -n $MEDIA_PLAYER ]] || exit 0
export MEDIA_PLAYER
qs_theme MEDIA
qs_anchor MEDIA
qs_start
