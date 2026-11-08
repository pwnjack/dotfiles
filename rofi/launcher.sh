#!/bin/bash
#
# Application Launcher
# Layout comes from options/launchertype: vertical or horizontal.
#

launcher=$(cat "$HOME/.config/options/launchertype" 2>/dev/null)
[[ "$launcher" == horizontal ]] || launcher=vertical

rofi -show drun -theme "$HOME/.config/rofi/themes/launcher/$launcher.rasi"
