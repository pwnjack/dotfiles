#!/bin/bash
#
# Tests for scripts/hyprland/medialib.sh and mediaexec.sh --plain against a fake
# playerctl: the player ranking (Playing with a title, then a title, then
# Playing, then the first on the bus) and the field separator that keeps an
# empty title from shifting the artist into its place. Then the media card's
# launcher, media-popover.sh, against a fake qs.
#
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TEST_DIR/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=scripts/lib/assert.sh
. "$ROOT/scripts/lib/assert.sh"

# The fake prints $FAKE_PLAYERS, one player per line as name|status|title|artist|album,
# joined with the separator playerctl is asked for (the byte after {{playerName}}).
mkdir -p "$TMP/bin"
cat > "$TMP/bin/playerctl" <<'EOF'
#!/bin/bash
sep=""
while [ $# -gt 0 ]; do
    case $1 in --format) sep=${2#\{\{playerName\}\}}; sep=${sep%%\{*}; shift ;; esac
    shift
done
[ -s "${FAKE_PLAYERS:-}" ] || exit 1
awk -F'|' -v OFS="$sep" '{ $1 = $1; print }' "$FAKE_PLAYERS"
EOF
chmod +x "$TMP/bin/playerctl"
export PATH="$TMP/bin:$PATH" FAKE_PLAYERS="$TMP/players"
# shellcheck source=scripts/hyprland/medialib.sh
. "$ROOT/scripts/hyprland/medialib.sh"
players() { printf '%s\n' "$@" > "$FAKE_PLAYERS"; }
winner() { media_snapshot | cut -d"$MEDIA_SEP" -f1; }
plain() { bash "$ROOT/scripts/hyprland/mediaexec.sh" --plain; }

players 'firefox|Paused|Some video|Channel|' 'spotify|Playing|Song|Artist|Album'
assert_eq "$(winner)" spotify "a Playing player with a title wins over a paused one"
players 'spotify|Playing|||' 'firefox|Paused|Some video|Channel|'
assert_eq "$(winner)" firefox "a paused player with a title beats Playing with no metadata"
players 'mpv|Stopped|||' 'spotify|Playing|||'
assert_eq "$(winner)" spotify "with no titles, the Playing player wins"
players 'mpv|Stopped|||' 'vlc|Stopped|||'
assert_eq "$(winner)" mpv "with nothing to prefer, the first on the bus wins"
: > "$FAKE_PLAYERS"
media_snapshot >/dev/null; assert_eq "$?" 1 "no player on the bus: nothing, and status 1"
assert_eq "$(media_player)" "" "and no player name"

players 'spotify|Playing||The Artist|The Album'
IFS="$MEDIA_SEP" read -r _ _ title artist album < <(media_snapshot)
assert_eq "$title|$artist|$album" "|The Artist|The Album" "an empty title stays empty; the artist does not shift into it"

players 'spotify|Playing|Before Taxes|The 1978ers|LP'
assert_eq "$(plain | sed 's/^[^ ]*  //')" "The 1978ers - Before Taxes" "--plain renders Artist - Title"
players 'spotify|Playing|Simon & Garfunkel||'
assert_contains "$(plain)" "Simon &amp; Garfunkel" "--plain escapes Pango entities"
players 'spotify|Playing|||'
assert_eq "$(plain)" "" "an empty title hides the module"

# The media card's launcher. The fake qs answers IPC only once a card was
# started, and a start records the player the card was given.
cat > "$TMP/bin/qs" <<'EOF'
#!/bin/bash
case " $* " in
    *" ipc call "*) [ -e "$QS_STATE/started" ] ;;
    *) printf '%s\n' "${MEDIA_PLAYER-unset}" >> "$QS_STATE/started" ;;
esac
EOF
printf '%s\n' '#!/bin/bash' 'echo "{\"x\": 100, \"y\": 5}"' > "$TMP/bin/hyprctl"
printf '%s\n' '#!/bin/bash' 'echo "$*" >> "$QS_STATE/notified"' > "$TMP/bin/notify-send"
chmod +x "$TMP/bin/qs" "$TMP/bin/hyprctl" "$TMP/bin/notify-send"
mkdir -p "$TMP/qs" "$TMP/home"
launch() {
    XDG_CONFIG_HOME="$ROOT" XDG_CACHE_HOME="$TMP/cache" HOME="$TMP/home" QS_STATE="$TMP/qs" \
        bash "$ROOT/scripts/hyprland/media-popover.sh" 2>&1
}

: > "$FAKE_PLAYERS"
launch; assert_eq "$?" 0 "the launcher: no player on the bus is not a failure"
[ ! -e "$TMP/qs/started" ]
check "and no card is started"
players 'firefox|Paused|Some video|Channel|' 'spotify|Playing|Song|Artist|Album'
launch; assert_eq "$?" 0 "the launcher starts a card"
assert_eq "$(cat "$TMP/qs/started" 2>/dev/null)" spotify "on the player the bar shows"
launch; assert_eq "$?" 0 "a second run reaches the running card"
assert_eq "$(wc -l < "$TMP/qs/started")" 1 "and starts no second one"
[ ! -e "$TMP/qs/notified" ]
check "nothing is reported as a failure"

test_summary media
