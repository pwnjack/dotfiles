#!/bin/bash
#
# Tests for scripts/hyprland/respawn.sh with a fake daemon that ends each run
# as scripted: crashes restart it, a clean end or a lost compositor stops it,
# a start made elsewhere during the delay wins, and a crash loop gives up with
# a notification.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TEST_DIR/../.." && pwd)"
RESPAWN="$ROOT/scripts/hyprland/respawn.sh"
TMP="$(mktemp -d)"
# Unique per run, since respawn.sh looks the daemon up by name, and within
# pgrep's 15 characters.
DAEMON="rsfake$$"
trap 'pkill -x "$DAEMON" 2>/dev/null; rm -rf "$TMP"' EXIT

# shellcheck source=scripts/lib/assert.sh
. "$ROOT/scripts/lib/assert.sh"

mkdir -p "$TMP/bin" "$TMP/run"
# The daemon pops the next step from $FAKE_STATUSES and records its argv. A
# number is an exit code, a signal name kills the daemon with that signal, and
# "hold" keeps it running for a while. Exit codes stand in for core-dumping
# signals (139 is SIGSEGV), which would leave core dumps on the host.
cat > "$TMP/bin/$DAEMON" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_LOG/runs"
step=$(head -n1 "$FAKE_STATUSES")
sed -i 1d "$FAKE_STATUSES"
case $step in
    hold) sleep 3; exit 0 ;;
    [A-Z]*) kill -s "$step" $$ ;;
esac
exit "${step:-0}"
EOF
cat > "$TMP/bin/logger" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_LOG/logger"
EOF
cat > "$TMP/bin/notify-send" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_LOG/notify"
EOF
chmod +x "$TMP/bin/"*
make_socket() {
    python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$TMP/run/wayland-test"
}
make_socket

# start_respawn <statuses> [env...] -- start the wrapper on the fake daemon in
# the background; its pid is in $wrapper.
start_respawn() {
    local statuses="$1"
    shift
    rm -rf "$TMP/log"
    mkdir -p "$TMP/log"
    # shellcheck disable=SC2086  # one step per word
    printf '%s\n' $statuses > "$TMP/statuses"
    env PATH="$TMP/bin:$PATH" FAKE_LOG="$TMP/log" FAKE_STATUSES="$TMP/statuses" \
        XDG_RUNTIME_DIR="$TMP/run" WAYLAND_DISPLAY=wayland-test RESPAWN_DELAY=0 \
        "$@" bash "$RESPAWN" "$DAEMON" --flag "two words" >/dev/null 2>&1 &
    wrapper=$!
}

# finish_respawn -- wait for the wrapper; sets $status, $runs, $logged and
# $notified.
finish_respawn() {
    wait "$wrapper"
    status=$?
    runs=$(wc -l < "$TMP/log/runs" 2>/dev/null || echo 0)
    logged=$(cat "$TMP/log/logger" 2>/dev/null)
    notified=$(cat "$TMP/log/notify" 2>/dev/null)
}

run_respawn() { start_respawn "$@"; finish_respawn; }

# wait_for CMD... -- poll up to 5 s.
wait_for() {
    local i
    for ((i = 0; i < 50; i++)); do "$@" && return 0; sleep 0.1; done
    return 1
}
restart_logged() { grep -q restarting "$TMP/log/logger" 2>/dev/null; }

run_respawn "139 134 0"
assert_eq "$runs" 3 "two crashes restart the daemon until it exits cleanly"
assert_eq "$status" 0 "the wrapper ends with the clean exit's status"
assert_contains "$logged" "$DAEMON exited with status 134; restarting it" "each restart is logged"
assert_eq "$(sort -u "$TMP/log/runs")" "--flag two words" "every run gets the same arguments"

for clean in 143 130 129 141; do
    run_respawn "$clean 0"
    assert_eq "$runs" 1 "exit status $clean, which bash also gives a clean signal death, is final"
done
assert_eq "$status" 141 "a clean signal's status is passed on"

run_respawn "TERM 0"
assert_eq "$runs" 1 "a real SIGTERM, as pkill sends, is final"
assert_eq "$status" 143 "SIGTERM's status is passed on"
run_respawn "USR1 0"
assert_eq "$runs" 2 "a real death by another signal restarts the daemon"

run_respawn "1 1 1 1 0" RESPAWN_BURST=3
assert_eq "$runs" 3 "three failures inside the window stop the restarts"
assert_eq "$status" 1 "giving up exits non-zero"
assert_contains "$notified" "$DAEMON keeps crashing" "giving up notifies"
assert_contains "$logged" "not restarting it" "giving up is logged"

run_respawn "1 1 1 1 1 0" RESPAWN_BURST=3 RESPAWN_WINDOW=0
assert_eq "$runs" 6 "failures older than the window do not count"
assert_eq "$notified" "" "a daemon under the limit never notifies"

run_respawn "139 0" WAYLAND_DISPLAY="$TMP/run/wayland-test"
assert_eq "$runs" 2 "an absolute WAYLAND_DISPLAY socket counts as a live compositor"

run_respawn "139 0" WAYLAND_DISPLAY=wayland-gone
assert_eq "$runs" 1 "no restart once the compositor socket is gone"
assert_eq "$status" 139 "the crash status is passed on when not restarting"

run_respawn "139 0" WAYLAND_DISPLAY=
assert_eq "$runs" 1 "no restart outside a Wayland session"

# Someone else starts the daemon while the wrapper waits out its delay, as the
# settings panel or waybar.sh would: the wrapper must not start a second one.
start_respawn "139 hold 0" RESPAWN_DELAY=1
wait_for restart_logged
env FAKE_LOG="$TMP/log" FAKE_STATUSES="$TMP/statuses" "$TMP/bin/$DAEMON" &
holder=$!
finish_respawn
assert_eq "$status" 0 "a daemon started elsewhere during the delay ends the wrapper quietly"
assert_eq "$runs" 2 "and the wrapper starts no second copy"
wait "$holder"

start_respawn "hold 0"
wait_for test -s "$TMP/log/runs"
env PATH="$TMP/bin:$PATH" FAKE_LOG="$TMP/log" FAKE_STATUSES="$TMP/statuses" \
    bash "$RESPAWN" "$DAEMON" >/dev/null 2>&1
assert_eq "$?" 0 "a wrapper for a daemon that is already running exits 0"
finish_respawn
assert_eq "$runs" 1 "and starts nothing"

# The session ends while the wrapper waits out its delay.
start_respawn "139 0" RESPAWN_DELAY=1
wait_for restart_logged
rm -f "$TMP/run/wayland-test"
finish_respawn
assert_eq "$runs" 1 "no restart when the compositor goes away during the delay"
make_socket

env PATH="$TMP/bin:$PATH" bash "$RESPAWN" no-such-daemon >/dev/null 2>&1
assert_eq "$?" 127 "a missing command exits 127"
bash "$RESPAWN" >/dev/null 2>&1
assert_eq "$?" 2 "no command is a usage error"

test_summary respawn
