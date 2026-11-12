#!/bin/bash
#
# System Updater
# Runs the configured AUR helper update command, then flatpak (if present)
#

# shellcheck source=scripts/lib/options.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/options.sh"
AURH=$(option "$HOME/.config/options/aurhelper")

if [ -z "$AURH" ]; then
    echo "AUR Helper not found"
    echo "This is likely because you skipped AUR installation, or set a custom AUR helper"
    echo "Please add your AUR helpers update command to $HOME/.config/options/aurhelper"
    echo
    read -p "Press ENTER to exit"
    exit 1
fi

echo "Updating system packages + AUR packages (SUDO required)"
$AURH
echo
read -p "Completed, note down any errors above, then press ENTER to move on."
clear

if command -v flatpak >/dev/null 2>&1; then
    echo "Updating flatpaks"
    flatpak update
    echo
    read -p "Completed, note down any errors above, then press ENTER to exit the updater."
    clear
fi
