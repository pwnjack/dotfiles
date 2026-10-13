#!/bin/bash
#
# Hyprland Startup Script
# Handles conditional startup actions based on configuration flags
#

# Render this machine's settings in the background, so it never delays the
# lock below; failures are left for the doctor (check_state).
bash "$HOME/.config/scripts/state/overlay.sh" sync >/dev/null 2>&1 &

if [ -f "$HOME/.config/options/autologin" ] && grep -q "enabled" "$HOME/.config/options/autologin"; then
    # Lock screen on autologin to ensure security
    command -v hyprlock >/dev/null 2>&1 && hyprlock
fi

if [ -f "$HOME/.config/options/protonvpn" ] && grep -qx "enabled" "$HOME/.config/options/protonvpn"; then
    if command -v protonvpn-app >/dev/null 2>&1; then
        protonvpn-app >/dev/null 2>&1 &
    fi
fi
