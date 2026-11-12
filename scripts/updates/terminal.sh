#!/bin/bash
#
# The human path from the update card: open options/terminal for the updates
# that need a person.
#   aur      scripts/settings/update.sh (paru; PKGBUILD review belongs here)
#   pacman   an interactive `sudo pacman -Syu`, to answer what --noconfirm cannot
#   flatpak  `flatpak update`
#
# Waybar is signalled from INSIDE the launched command, when it exits: a
# client-style terminal returns as soon as it hands the window off, so a
# signal sent after the launcher returns would fire before the update began.
#
set -uo pipefail

case "${1-}" in
    aur) cmd=("$HOME/.config/scripts/settings/update.sh") ;;
    pacman) cmd=(bash -c 'sudo pacman -Syu; read -rp "Press Enter to close"') ;;
    flatpak) cmd=(bash -c 'flatpak update; read -rp "Press Enter to close"') ;;
    *) echo 'Usage: terminal.sh aur|pacman|flatpak' >&2; exit 2 ;;
esac

# The option may carry arguments (scripts/settings/terminal.sh); the binary is
# its first word.
# shellcheck source=scripts/lib/options.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/options.sh"
read -r term _ <<< "$(option "$HOME/.config/options/terminal" ghostty)"
# shellcheck disable=SC2016  # "$@" must expand in the INNER bash
exec "$term" -e bash -c '"$@"; pkill -x -RTMIN+9 waybar' bash "${cmd[@]}"
