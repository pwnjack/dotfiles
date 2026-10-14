#!/bin/bash
#
# Lock the session. The one lock path: Super+L, the power menu and hypridle's
# lock_cmd (so idle and before-sleep too, which go through loginctl
# lock-session) all run this.
#
# The lock comes first and the save second. Locking is the security boundary,
# and on suspend logind waits only InhibitDelayMaxSec (5 s) for the lock before
# sleeping anyway, so nothing may stand in front of hyprlock. A running
# recording is saved by a detached record.sh stop started just before hyprlock
# is exec'd: it runs its own escalation and toasts to completion, and if it is
# missing or fails the lock still happens. The clip may therefore end with about
# a second of the lock screen. record.sh stop does nothing when nothing
# records, and cancels a countdown.
#
# Never a second hyprlock, and the guard fails closed: the lock is skipped only
# when a hyprlock of this user is really running (pgrep). A flock on a descriptor
# the exec'd hyprlock inherits makes concurrent callers queue for up to 1 s so
# the first one's hyprlock is visible to the next, but a lock file that cannot
# be opened or a lock still held after that second never prevent locking; the
# runtime dir is never /tmp, where another user could plant the file. A stale
# hyprlock that no longer holds the session lock still counts as locked; this
# script does not look further than the process.
# Arguments go to hyprlock: the idle listener in hypr/hypridle.conf passes
# --grace 5, and the live check uses --grace 30.
#
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
lock_file="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/lock.sh.lock"
if { command exec 9>"$lock_file"; } 2>/dev/null; then
    flock -w 1 9
fi
pgrep -xu "$(id -u)" hyprlock >/dev/null && exit 0
setsid -f "$config_dir/scripts/capture/record.sh" stop </dev/null >/dev/null 2>&1 9>&-
exec hyprlock "$@"
