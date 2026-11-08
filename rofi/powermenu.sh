#!/bin/bash
#
# Power Menu
# Lock, suspend, logout, reboot and shutdown. Logout, reboot and shutdown ask
# for confirmation, and the confirmation starts on No, so a double Enter is
# never destructive.
#
# Rows are Pango markup (the theme-sized glyph over a small label), so rofi reports
# the selected index (-format i) rather than the row text.
#

theme="$HOME/.config/rofi/themes/powermenu/main.rasi"

# Nerd Font glyphs, escaped so no editor can silently drop them.
lock=$'\U000F0341' suspend=$'\U000F0904' logout=$'\U000F0206' reboot=$'\uEAD2' shutdown=$'\U000F0425'
yes=$'\uF058' no=$'\uF52F'

# row GLYPH LABEL: one menu entry, glyph above its label.
row() {
    printf "%s\n<span font='11'>%s</span>|" "$1" "$2"
}

# confirmed QUESTION: true only if the user picks Yes.
confirmed() {
    local answer
    answer=$({ row "$no" No; row "$yes" Yes; } | rofi -dmenu -markup-rows -sep '|' -eh 2 -format i -no-custom \
        -theme-str 'window {width: 350px;}' \
        -theme-str 'mainbox {children: [ "message", "listview" ];}' \
        -theme-str 'listview {columns: 2; lines: 1;}' \
        -mesg "$1" \
        -theme "$theme")
    [[ "$answer" == 1 ]]
}

chosen=$({
    row "$lock" Lock
    row "$suspend" Suspend
    row "$logout" Logout
    row "$reboot" Reboot
    row "$shutdown" Shutdown
} | rofi -dmenu -markup-rows -sep '|' -eh 2 -format i -no-custom \
    -p $'\uF007'" $USER" \
    -mesg $'\U000F0954'" Uptime: $(uptime -p | sed 's/up //')" \
    -theme "$theme")

# Lock goes through lock.sh, the one lock path (it locks at once, a running
# recording is saved by a detached stop, and it never starts a second
# hyprlock); suspend goes through hypridle,
# whose before_sleep_cmd locks the session the same way.
# Log out, reboot and shut down end the session, and systemd would only SIGTERM
# a running recorder, which may lose the clip: save it first, bounded so a stuck
# recorder cannot hold the menu.
stop_recording() { timeout -k 1 12 "$HOME/.config/scripts/capture/record.sh" stop; }

case "$chosen" in
    0) "$HOME/.config/scripts/hyprland/lock.sh" ;;
    1) systemctl suspend ;;
    2) confirmed "Log out of Hyprland?" && { stop_recording; hyprctl dispatch 'hl.dsp.exit()'; } ;;
    3) confirmed "Reboot now?" && { stop_recording; systemctl reboot; } ;;
    4) confirmed "Shut down now?" && { stop_recording; systemctl poweroff; } ;;
esac
