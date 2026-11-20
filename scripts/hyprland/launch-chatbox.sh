#!/bin/bash
#
# Toggle the AI sidebar (Super+A): aichat in a ghostty window on the special
# workspace "aichat".
#
# Placement, float and workspace all come from the "ai-sidebar" window
# rule in hypr/config/software/rules.lua, which matches the class set here.
#
# ghostty is started from this script rather than through `hyprctl dispatch
# exec`, so it inherits the API keys loaded from .env below; an exec would run
# with Hyprland's environment instead.
#
# aichat copies a role into a session once, when the session starts, and
# `.clear messages` keeps that copy. --empty-session restarts the "sidebar"
# session on every launch, so each new window picks up the current
# aichat/roles/sidebar.md; toggling the window keeps the conversation.
# An emptied session still keeps the model it was saved with, so the default
# model is read from aichat's config and passed explicitly.
#

class="aichat.sidebar"

for c in hyprctl jq aichat ghostty; do
    command -v "$c" >/dev/null 2>&1 || { notify-send "AI sidebar" "$c is not installed" 2>/dev/null; exit 1; }
done

if hyprctl clients -j | jq -e --arg class "$class" 'any(.[]; .class == $class)' >/dev/null; then
    hyprctl dispatch 'hl.dsp.workspace.toggle_special("aichat")'
    exit 0
fi

if [ -f "$HOME/.config/.env" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$HOME/.config/.env"
    set +a
fi

args=(-r sidebar -s sidebar --empty-session)
model=$(aichat --info </dev/null 2>/dev/null | awk '$1 == "model" { print $2 }')
[ -n "$model" ] && args=(-m "$model" "${args[@]}")

setsid -f ghostty --class="$class" --config-file="$HOME/.config/ghostty/ai-sidebar" \
    -e aichat "${args[@]}" >/dev/null 2>&1
