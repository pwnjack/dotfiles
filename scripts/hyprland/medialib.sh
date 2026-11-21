#!/bin/bash
#
# Shared player selection for the waybar media module. Sourced, not run.
#
# playerctl with no --player picks the first name on the bus, which is
# registration order and has nothing to do with what is playing: with Firefox
# and Spotify both open the bar would sit on whichever registered first, even
# while the other one plays. There used to be a left-click toggle that pinned
# the module to options/mediaplayer to work around exactly that; choosing the
# right player here removes the reason for the toggle.
#
# The rule, best match first:
#
#   1. Playing and has a title   -- what you actually want to see
#   2. has a title               -- paused, but real metadata to show
#   3. Playing                   -- something is making noise; name it, even
#                                   though the bar will hide an empty title
#   4. the first player on the bus
#
# Rank 1 before 2 rather than "any Playing player wins" because Spotify sits on
# the bus Playing with empty metadata in some states, and that would blank a
# bar that had a perfectly good paused title to show.
#
# Display (mediaexec.sh), transport (mediactl.sh) and the media card's
# launcher (media-popover.sh) all go through this, so the title on the bar, the
# player your scroll wheel moves and the one the card opens on are always the
# same one -- there is one winner, not one per surface.
#

# Field separator: ASCII unit separator, and NOT a tab.
#
# `read` collapses runs of IFS *whitespace* into one delimiter, and a tab is
# whitespace. Spotify sits on the bus with an empty title but a real artist,
# which emits two adjacent separators -- with tabs those collapse and every
# later field shifts left, so the artist is read as the title and the album as
# the artist. That is the bug that used to put "firefox" in the album slot.
# \x1f is not whitespace, so an empty field stays an empty field.
MEDIA_SEP=$'\x1f'

# One line per player. The separator has to be a real byte before playerctl
# sees it: playerctl's format language does not interpret backslash escapes,
# so a literal "\t" in the format string would come back as two characters.
_media_snapshot_all() {
    playerctl -a metadata \
        --format "{{playerName}}$MEDIA_SEP{{status}}$MEDIA_SEP{{title}}$MEDIA_SEP{{artist}}$MEDIA_SEP{{album}}" \
        2>/dev/null
}

# Echoes the winning line (five MEDIA_SEP-separated fields), or nothing when no
# player is on the bus. Fields may contain spaces; only a newline inside a
# title would confuse this, and no player emits one.
# Everything is `local`: this file is sourced, and a bare `status` or `title`
# would otherwise land in the caller's namespace.
media_snapshot() {
    local line state title first="" titled="" playing=""

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        IFS="$MEDIA_SEP" read -r _ state title _ <<< "$line"

        # Rank 1 is decided the moment it is seen; the rest are remembered as
        # the best candidate so far and settled after the loop.
        if [ "$state" = "Playing" ] && [ -n "$title" ]; then
            printf '%s\n' "$line"
            return 0
        fi
        [ -z "$first" ] && first="$line"
        [ -n "$title" ] && [ -z "$titled" ] && titled="$line"
        [ "$state" = "Playing" ] && [ -z "$playing" ] && playing="$line"
    done < <(_media_snapshot_all)

    for line in "$titled" "$playing" "$first"; do
        [ -n "$line" ] && printf '%s\n' "$line" && return 0
    done
    return 1
}

# Just the player name of the winner, for `playerctl -p`.
media_player() {
    local name
    IFS="$MEDIA_SEP" read -r name _ < <(media_snapshot)
    printf '%s' "$name"
}
