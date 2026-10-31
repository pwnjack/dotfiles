#!/bin/bash
#
# Shared start-up for the on-demand Quickshell launchers in scripts/hyprland/.
# A launcher sources this, calls qs_launch (checks and the launch lock), asks
# a running instance with qs_ipc, exports its palette with qs_theme and its own
# settings, then ends with qs_start. Requests are serialised, and the
# Quickshell process exits when its surface closes, so nothing runs between
# visits. Run from a keybind or a Waybar click, stderr goes nowhere: every
# failure is also a notification.
#
# Sets config_dir, and cache_dir (~/.cache/<launcher name>), for the caller.
#

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/${0##*/}"
cache_dir=${cache_dir%.sh}
qs_app=Quickshell

# Neither a missing notify-send nor a closed stderr may stop it exiting 1.
qs_fail() {
    if command -v notify-send >/dev/null 2>&1; then notify-send -a "$qs_app" "$qs_app" "$1" 2>/dev/null || true; fi
    echo "$1" >&2 || true
    exit 1
}

# qs_launch <quickshell dir> <IPC target> <notification app> <noun>
qs_launch() {
    qs_entry="$config_dir/quickshell/$1/shell.qml" qs_target=$2 qs_app=$3 qs_noun=$4
    command -v qs >/dev/null 2>&1 || qs_fail "Install quickshell to show $qs_noun."
    command -v flock >/dev/null 2>&1 || qs_fail "flock is required for $qs_noun."
    mkdir -p "$cache_dir" || qs_fail "Cannot create $cache_dir for $qs_noun."
    exec 9>"$cache_dir/launch.lock" || qs_fail "Cannot open the lock for $qs_noun in $cache_dir."
    flock -w 10 9 || qs_fail "${qs_noun^} is still starting; try again."
}

qs_ipc() { qs -p "$qs_entry" ipc call "$qs_target" "$@" 9>&-; }

# qs_option <name> <default>: the first line of options/<name>, or the default.
qs_option() { head -n1 "$config_dir/options/$1" 2>/dev/null || printf '%s\n' "$2"; }

# qs_theme <PREFIX> [role...]: exports <PREFIX>_BACKGROUND, _FOREGROUND,
# _ACCENT, _ON_ACCENT, one <PREFIX>_<ROLE> per extra role, and <PREFIX>_FONT.
# Tested as a condition: under set -e a failure inside $(...) would end the
# launcher silently. A palette that was never generated reads as palette.sh's
# fallback; only a failing helper leaves nothing exported, and then the QML
# uses its built-in colours.
qs_theme() {
    local prefix=$1 name value font foreground accent on_accent
    shift
    # shellcheck source=scripts/theming/palette.sh
    source "$config_dir/scripts/theming/palette.sh" || qs_fail "Cannot load the theme palette for $qs_noun."
    local -a wal
    # shellcheck disable=SC2034  # read by role_load and wal_role
    local -A role=()
    local -a extra=()
    if wal_load && role_load && foreground=$(wal_readable_on "${wal[0]}") \
        && accent=$(wal_role primary) && on_accent=$(wal_role on_primary); then
        for name; do
            value=$(wal_role "$name") || { extra=(); break; }
            extra+=("${prefix}_${name^^}=$value")
        done
        export "${prefix}_BACKGROUND=${wal[0]}" "${prefix}_FOREGROUND=$foreground" \
            "${prefix}_ACCENT=$accent" "${prefix}_ON_ACCENT=$on_accent" "${extra[@]}"
    fi
    font=$(qs_option font '')
    export "${prefix}_FONT=$font"
}

qs_start() {
    local attempt
    qs -p "$qs_entry" --no-duplicate --daemonize >"$cache_dir/session.log" 2>&1 9>&- \
        || qs_fail "${qs_noun^} failed to start; see $cache_dir/session.log"
    # Hold the lock until IPC answers, so a quick second press closes this
    # instance instead of racing a second start.
    for ((attempt = 0; attempt < 60; attempt++)); do
        if qs_ipc ping >/dev/null 2>&1; then return 0; fi
        sleep 0.05
    done
    qs_fail "${qs_noun^} did not answer; see $cache_dir/session.log"
}
