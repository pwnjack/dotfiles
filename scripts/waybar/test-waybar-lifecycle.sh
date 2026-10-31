#!/bin/bash
# Tests for the Waybar reload and visibility lifecycle scripts.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

mkdir -p "$TMP/bin"
# These single-quoted lines are intentionally written verbatim into the fakes.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'printf "%s\n" "$*" > "$PKILL_LOG"' \
    'exit "$PKILL_STATUS"' > "$TMP/bin/pkill"
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'printf "started by %s\n" "$(ps -o args= -p "$PPID")" > "$WAYBAR_LOG"' > "$TMP/bin/waybar"
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'case "$*" in' \
    '    *" get-property "*) exit 0 ;;' \
    '    *" list") printf "%s\n" "org.kde.StatusNotifierItem-proton.vpn.app.gtk-123 123 proton" "org.example.Unrelated 456 other" ;;' \
    '    *" call "*) printf "%s\n" "$*" >> "$BUSCTL_LOG" ;;' \
    'esac' > "$TMP/bin/busctl"
printf '%s\n' '#!/bin/bash' 'exit 0' > "$TMP/bin/sleep"
# respawn.sh looks for a running bar before it starts one; the host's own
# Waybar must not count.
printf '%s\n' '#!/bin/bash' 'exit 1' > "$TMP/bin/pgrep"
chmod +x "$TMP/bin/pkill" "$TMP/bin/waybar" "$TMP/bin/busctl" "$TMP/bin/sleep" "$TMP/bin/pgrep"

run_script() {
    : > "$TMP/pkill.log"
    : > "$TMP/busctl.log"
    rm -f "$TMP/waybar.log"
    rm -rf "$TMP/state" "$TMP/cache"
    # The renderers waybar.sh runs before a start write here, never to the
    # real ~/.local/state or ~/.cache, and read no live options or palette.
    PKILL_LOG="$TMP/pkill.log" WAYBAR_LOG="$TMP/waybar.log" \
        BUSCTL_LOG="$TMP/busctl.log" \
        BAR_OPTIONS="$TMP/no-options" BAR_INCLUDE="$TMP/state/bar.jsonc" BAR_CSS="$TMP/state/bar.css" \
        CLOCK_OPTION="$TMP/no-options/clock" CLOCK_INCLUDE="$TMP/state/clock.jsonc" \
        XDG_CACHE_HOME="$TMP/cache" \
        PKILL_STATUS="$2" PATH="$TMP/bin:$PATH" bash "$1"
}

assert_running_case() {
    local script="$1" signal="$2" label="$3"
    run_script "$script" 0
    if [ "$(<"$TMP/pkill.log")" = "$signal -x waybar" ] &&
       [ ! -e "$TMP/waybar.log" ] &&
       { [ "$signal" != -USR2 ] || grep -qF \
           'RegisterStatusNotifierItem s org.kde.StatusNotifierItem-proton.vpn.app.gtk-123' \
           "$TMP/busctl.log"; }; then
        pass "$label"
    else
        fail "$label"
    fi
}

assert_absent_case() {
    local script="$1" label="$2" attempt
    run_script "$script" 1
    for ((attempt = 0; attempt < 100; attempt++)); do
        [ ! -e "$TMP/waybar.log" ] || break
        sleep 0.01
    done
    # Started under respawn.sh, so a crash brings the bar back.
    if [ -e "$TMP/waybar.log" ] && [ -e "$TMP/state/bar.css" ] && [ -e "$TMP/state/clock.jsonc" ] &&
       [ -e "$TMP/cache/wal/colors-waybar.css" ] && grep -q '/hyprland/respawn.sh waybar$' "$TMP/waybar.log"; then
        pass "$label"
    else
        fail "$label"
    fi
}

echo "waybar lifecycle"

assert_running_case "$TEST_DIR/waybar.sh" -USR2 \
    "reload sends SIGUSR2 and restores existing tray items"
assert_absent_case "$TEST_DIR/waybar.sh" \
    "reload starts Waybar when it is absent"
assert_running_case "$TEST_DIR/waybartoggle.sh" -USR1 \
    "visibility toggle keeps the running process and sends SIGUSR1"
assert_absent_case "$TEST_DIR/waybartoggle.sh" \
    "visibility toggle starts Waybar when it is absent"

test_summary
