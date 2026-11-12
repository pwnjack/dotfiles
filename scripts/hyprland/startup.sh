#!/bin/bash
#
# Hyprland Startup Script
# Handles conditional startup actions based on configuration flags
#

# Render this machine's settings in the background, so it never delays the
# lock below; failures are left for the doctor (check_state).
bash "$HOME/.config/scripts/state/overlay.sh" sync >/dev/null 2>&1 &

# shellcheck source=scripts/lib/options.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/options.sh"

# Lock the screen after an autologin, through the one lock path. It runs in the
# foreground, so nothing below starts before the lock is up.
if [ "$(option "$HOME/.config/options/autologin")" = enabled ]; then
    command -v hyprlock >/dev/null 2>&1 && bash "$HOME/.config/scripts/hyprland/lock.sh"
fi

if [ "$(option "$HOME/.config/options/protonvpn")" = enabled ]; then
    if command -v protonvpn-app >/dev/null 2>&1; then
        protonvpn-app >/dev/null 2>&1 &
    fi
fi

# The desktop clock (eww) when options/desktop-clock says so; the script does
# nothing without eww, and runs in the background so it never delays login.
bash "$HOME/.config/scripts/desktop-clock/desktop-clock.sh" start >/dev/null 2>&1 &
