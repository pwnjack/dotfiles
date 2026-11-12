#!/bin/bash
#
# Application Launcher
# Layout comes from options/launchertype: vertical or horizontal.
#

# shellcheck source=scripts/lib/options.sh
. "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib/options.sh"
launcher=$(option "$HOME/.config/options/launchertype")
[[ "$launcher" == horizontal ]] || launcher=vertical

rofi -show drun -theme "$HOME/.config/rofi/themes/launcher/$launcher.rasi"
