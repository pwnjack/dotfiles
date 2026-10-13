#!/usr/bin/env bash
# Start Spotify through spotify-launcher, re-applying SpotX (ad blocking) and,
# when it is set up, Spicetify on top, whenever the client is unpatched.
#
#   scripts/spotify/launch.sh [URI]
#
# The desktop entry written by setup.sh runs this instead of spotify-launcher.
#
# spotify-launcher unpacks each update into a new directory and swaps it in
# whole (src/extract.rs, atomic_swap), which drops any patch. MARKER lives in
# that directory, so it disappears exactly when the patch does: its absence is
# the one signal that patching is needed. It sits beside the binary, not in
# Apps/: Spicetify's restore and apply both delete and rebuild Apps/ whole.
#
# Order matters. SpotX patches the stock Apps/xpui.spa; Spicetify then backs up
# that patched file (clearing its own stale backup, which it does whenever the
# client is backupable) and unpacks it. A client Spicetify has already unpacked
# has no xpui.spa, which SpotX refuses, so `spicetify restore` runs first then.
# SpotX gets -f: when its own backup exists it restores the stock files and
# patches again, so a run SpotX failed halfway is simply repeated.
# Spicetify takes the backup version from prefs, which still names the old
# client before an update's first launch. Stamp its existing version key from
# spotify-launcher's state before the backup, or later refreshes reject it.
#
# MARKER means "SpotX applied", and is written as soon as it is. Rebuilding
# Apps/ drops SpotX's stock xpui.bak, so a client that has been through
# Spicetify cannot be patched again: Spicetify's backup is the patched copy,
# and SpotX refuses it ("Detected SpotX-Bash but no backup file"). A Spicetify
# failure therefore gets its own toast naming its fix, and is not retried.
#
# SpotX exits 0 on a client newer than it supports, applying what still
# matches; the versions it logs are compared so that case gets a warning.
#
# SpotX runs `pkill -9 '[sS]potify'`, which matches process names: this file
# must never be named with "spotify" in it, or SpotX kills it mid-patch.
#
# Patching never blocks Spotify: on any failure it starts unpatched, with a
# toast naming the log. A running Spotify is never updated or patched; the call
# is handed to it as is (its single instance takes the URI). That check runs
# only while holding the lock: before it, a sibling launch's own update
# (spotify-launcher --no-exec) would look like a running client.
#
# Test seams: SPOTIFY_INSTALL_DIR (the client directory), XDG_DATA_HOME (the
# launcher state), SPOTX_URL, and the commands spotify-launcher, spicetify,
# curl, pgrep and notify-send on PATH.
set -uo pipefail

install="${SPOTIFY_INSTALL_DIR:-$HOME/.local/share/spotify-launcher/install/usr/share/spotify}"
apps="$install/Apps"
MARKER="$install/.spotx-patched"
SPOTX_URL="${SPOTX_URL:-https://raw.githubusercontent.com/SpotX-Official/SpotX-Bash/main/spotx.sh}"
state="${XDG_STATE_HOME:-$HOME/.local/state}/spotify"
log="$state/patch.log"
spicetify_config="${XDG_CONFIG_HOME:-$HOME/.config}/spicetify/config-xpui.ini"
launcher_state="${XDG_DATA_HOME:-$HOME/.local/share}/spotify-launcher/state.json"
newer=0

notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a Spotify -i spotify-launcher "$@" || true
}

start() {
    exec spotify-launcher --skip-update "$@"
}

# Spicetify only when this user has set it up; installed alone it has no theme
# to apply and would create a config of its own.
use_spicetify() {
    command -v spicetify >/dev/null 2>&1 && [ -f "$spicetify_config" ]
}

# Called under the patch lock, with Spotify confirmed not running. Only stamp
# an existing prefs key; incomplete launcher or Spicetify state is left alone.
stamp_prefs_version() {
    local version prefs tmp
    [ -r "$launcher_state" ] || return 0
    version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$launcher_state")
    [[ "$version" =~ ^[0-9]+: ]] && version=${version#*:}
    [[ "$version" =~ ^[0-9]+(\.[0-9]+)+(\.g[[:xdigit:]]+)?$ ]] || return 0
    prefs=$(sed -n 's/^prefs_path[[:space:]]*=[[:space:]]*//; T; s/[[:space:]]*$//p' "$spicetify_config" | head -n1)
    prefs=${prefs//\$HOME/$HOME}
    prefs=${prefs/#\~/$HOME}
    # Replace the file a symlink points at, never the link itself.
    [ -f "$prefs" ] && prefs=$(readlink -f -- "$prefs") || return 0
    grep -q '^app\.last-launched-version=' "$prefs" || return 0
    tmp=$(mktemp "$prefs.XXXXXX") || return 0
    if sed "s/^app\\.last-launched-version=.*/app.last-launched-version=\"$version\"/" "$prefs" >"$tmp" \
            && chmod --reference="$prefs" "$tmp" && mv -- "$tmp" "$prefs"; then
        return 0
    fi
    rm -f -- "$tmp"
    return 0
}

# Returns 0 when everything applied, 1 when SpotX did not (no marker, retried
# next launch), 2 when SpotX applied but Spicetify failed (marker written).
# Sets newer=1 when the client is newer than SpotX supports.
#
# SpotX ends its output with terminal escapes and no newline, so the log lines
# written here start with a newline of their own, and nothing parses them back.
apply_patches() {
    local tmp="" rc=0 restored=0
    newer=0
    {
        printf '\n== %s patching %s\n' "$(date '+%F %T')" "$install"
        tmp=$(mktemp -d) || rc=1
        # Download first: a run that cannot get SpotX must not touch the client.
        [ "$rc" = 0 ] && { curl -fsSL --retry 2 --max-time 60 -o "$tmp/spotx.sh" "$SPOTX_URL" || rc=1; }
        if [ "$rc" = 0 ] && [ ! -f "$apps/xpui.spa" ] && use_spicetify; then
            if timeout 300 spicetify -q -n restore </dev/null; then restored=1; else rc=1; fi
        fi
        [ "$rc" = 0 ] && { timeout 600 bash "$tmp/spotx.sh" --noninteractive --nocolor -f -P "$install" </dev/null || rc=1; }
        if [ "$rc" = 0 ]; then
            : >"$MARKER"
            newer_than_supported && newer=1
            if use_spicetify; then
                stamp_prefs_version >/dev/null 2>&1
                timeout 300 spicetify -q -n backup apply </dev/null || rc=2
            fi
        elif [ "$restored" = 1 ]; then
            # SpotX failed after the theme was taken off: put it back, unchanged.
            timeout 300 spicetify -q -n apply </dev/null || true
        fi
        printf '\n== exit %s\n' "$rc"
    } >"$log" 2>&1
    [ -n "$tmp" ] && rm -rf -- "$tmp"
    return "$rc"
}

# SpotX logs "Latest supported version: X" and "Detected client version: Y",
# where Y is N/A when it cannot ask the binary; it then names the version it
# read from xpui.js as "Detected Spotify Y". Only real version numbers count.
newer_than_supported() {
    local supported detected
    supported=$(sed -n 's/.*Latest supported version: \([0-9][0-9.]*\).*/\1/p' "$log" | head -n1)
    detected=$(sed -n -e 's/.*Detected client version: \([0-9][0-9.]*\).*/\1/p' \
        -e 's/.*Detected Spotify \([0-9][0-9.]*\).*/\1/p' "$log" | head -n1)
    [ -n "$supported" ] && [ -n "$detected" ] && [ "$supported" != "$detected" ] \
        && [ "$(printf '%s\n%s\n' "$supported" "$detected" | sort -V | tail -n1)" = "$detected" ]
}

# Any of this user's Spotify processes, or a spotify-launcher that has not yet
# exec'd it (the kernel truncates its name to 15 characters).
running() {
    pgrep -u "$(id -u)" -x 'spotify|spotify-launche' >/dev/null 2>&1
}

command -v spotify-launcher >/dev/null 2>&1 || {
    echo "spotify: spotify-launcher is not installed" >&2
    exit 1
}

mkdir -p "$state"
# Two launches in a row (a double click, a spotify: link) must not update or
# patch at once; the second waits here, then finds the first one's Spotify.
# Fd 9 is closed before exec, or Spotify would hold the lock.
exec 9>"$state/patch.lock"
flock 9
if running; then
    exec 9>&-
    start "$@"
fi
# Bounded: a stalled download must not hold every queued launch forever.
timeout 600 spotify-launcher --no-exec >"$state/update.log" 2>&1 \
    || echo "spotify: the update check failed; starting what is installed" >&2
if [ -d "$apps" ] && [ ! -e "$MARKER" ]; then
    notify "Patching Spotify" "Applying SpotX before Spotify starts; this takes a few seconds."
    apply_patches
    case $? in
        1) notify -u critical "Spotify started without SpotX" \
               "Patching failed, so ads are back; the next start retries. If it keeps failing, close Spotify and run: spotify-launcher --force-update --no-exec. Details: $log" ;;
        2) notify "Spicetify theme not applied" \
               "SpotX is applied. Run 'spicetify backup apply' to restore the theme. Details: $log" ;;
    esac
    if [ "$newer" = 1 ]; then
        notify "SpotX may be incomplete" \
            "This Spotify build is newer than SpotX supports, so some ads may show. Details: $log"
    fi
fi
exec 9>&-
start "$@"
