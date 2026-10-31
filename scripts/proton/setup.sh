#!/bin/bash
#
# Proton VPN on demand
# proton-vpn-daemon enables proton.VPN.service at boot, and re-enables and
# restarts it on every upgrade. The daemon, about 150 MB of Python, serves only
# split tunnelling: the VPN itself and its kill switch work without it, and the
# app reports split tunnelling as unavailable while it is off. This disables
# the unit, stops it unless the Proton app is open, and installs a pacman hook
# that does the same after every install or upgrade of proton-vpn-daemon.
# Whether the app itself starts at login stays the Startup page's Proton VPN
# switch (options/protonvpn).
#
# Undo: sudo rm /etc/pacman.d/hooks/zz-proton-vpn-on-demand.hook
#       sudo systemctl enable --now proton.VPN.service
#

UNIT="proton.VPN.service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SOURCE="$SCRIPT_DIR/proton-vpn-on-demand.hook"
INSTALLED_HOOK="/etc/pacman.d/hooks/zz-proton-vpn-on-demand.hook"

if [[ "$EUID" -eq 0 ]]; then
    echo "✗ Run this as your own user, not with sudo: bash $SCRIPT_DIR/setup.sh" >&2
    echo "  It asks for your sudo password itself when it needs to." >&2
    exit 1
fi

if ! pacman -Q proton-vpn-daemon >/dev/null 2>&1; then
    echo "✓ proton-vpn-daemon is not installed; nothing to do"
    exit 0
fi

# Same test as the bar refresh hook's: pacman runs the hook's Exec as root.
if [[ ! -L "$INSTALLED_HOOK" ]] && cmp -s "$HOOK_SOURCE" "$INSTALLED_HOOK" &&
   [[ "$(stat -c '%U:%G %a' "$INSTALLED_HOOK" 2>/dev/null)" = "root:root 644" ]]; then
    echo "✓ Upgrade hook is already current"
elif sudo install -D -m 0644 -o root -g root "$HOOK_SOURCE" "$INSTALLED_HOOK"; then
    echo "✓ Installed $INSTALLED_HOOK"
else
    echo "✗ Failed to install the upgrade hook"
    exit 1
fi

if ! systemctl is-enabled --quiet "$UNIT"; then
    echo "✓ $UNIT is already off at boot"
elif sudo systemctl disable --quiet "$UNIT"; then
    echo "✓ $UNIT no longer starts at boot"
else
    echo "✗ Failed to disable $UNIT"
    exit 1
fi

if ! systemctl is-active --quiet "$UNIT"; then
    echo "✓ $UNIT is not running"
elif pgrep -x protonvpn-app >/dev/null; then
    echo "• $UNIT stays up while the Proton app is open; it is gone after the next boot"
elif sudo systemctl stop "$UNIT"; then
    echo "✓ Stopped $UNIT"
else
    echo "✗ Failed to stop $UNIT"
    exit 1
fi
