#!/bin/bash
#
# desktop-clock.sh and eww/apply_wal_colors.sh against a stub `eww` that
# records its calls and models a daemon with one window. HOME, the config and
# the cache are throwaway directories: the real eww daemon, the real options
# and the real matugen palette cache are never touched.
#

# shellcheck disable=SC2016  # the SCSS variables ($clock-font, $foreground) are literal text
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/assert.sh
. "$ROOT/scripts/lib/assert.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

home="$tmp/home" cfg="$tmp/config" cache="$tmp/cache" bin="$tmp/bin" state="$tmp/state"
mkdir -p "$home" "$cfg/options" "$cfg/scripts" "$cache" "$bin" "$state"
cp -r "$ROOT/eww" "$cfg/eww"
cp -r "$ROOT/scripts/desktop-clock" "$cfg/scripts/desktop-clock"
cp -r "$ROOT/scripts/theming" "$cfg/scripts/theming"

# The stub's "daemon" and "window" are two files under $state. STUB_FAIL_SCREEN
# makes `open --screen` fail, as eww does for a monitor it does not know.
cat > "$bin/eww" <<'STUB'
#!/bin/bash
echo "$*" >> "$STUB_STATE/calls"
shift 2   # --config <dir>
case "$1" in
    ping) [ -e "$STUB_STATE/daemon" ] ;;
    daemon)
        touch "$STUB_STATE/daemon"
        # A daemon that outlives the call and inherits every descriptor it was given.
        if [ -n "${STUB_LINGER:-}" ]; then sleep 3 & fi ;;
    open)
        [ -e "$STUB_STATE/daemon" ] || exit 1
        if [ -n "${STUB_FAIL_SCREEN:-}" ] && [[ " $* " == *" --screen "* ]]; then echo "Failed to get monitor" >&2; exit 1; fi
        touch "$STUB_STATE/open" ;;
    close) rm -f "$STUB_STATE/open" ;;
    active-windows) [ -e "$STUB_STATE/open" ] && echo "clock: clock"; exit 0 ;;
    reload)
        [ -e "$STUB_STATE/daemon" ] || exit 1
        if [ -n "${STUB_FAIL_RELOAD:-}" ]; then echo "Error: stylesheet does not parse" >&2; exit 1; fi ;;
    kill)
        rm -f "$STUB_STATE/open"
        # eww queues the shutdown: the daemon still answers ping for a moment.
        if [ -n "${STUB_SLOW_KILL:-}" ]; then (sleep 0.3; rm -f "$STUB_STATE/daemon") </dev/null >/dev/null 2>&1 &
        else rm -f "$STUB_STATE/daemon"; fi ;;
esac
STUB
# Two monitors of different models, two of one model.
cat > "$bin/hyprctl" <<'STUB'
#!/bin/bash
echo '[{"name":"FIX-A","model":"Alpha"},{"name":"FIX-B","model":"Beta"},{"name":"FIX-C","model":"Twin"},{"name":"FIX-D","model":"Twin"}]'
STUB
chmod +x "$bin/eww" "$bin/hyprctl"

clock() {
    HOME="$home" XDG_CONFIG_HOME="$cfg" XDG_CACHE_HOME="$cache" STUB_STATE="$state" \
        PATH="$bin:$PATH" bash "$cfg/scripts/desktop-clock/desktop-clock.sh" "$@" 2>&1
}
calls() { cat "$state/calls" 2>/dev/null; }
reset() { rm -f "$state"/*; }
opt() { printf '%s\n' "$2" > "$cfg/options/$1"; }
font_scss="$cache/eww/font.scss"
colors_scss="$cache/wal/eww-colors.scss"

opt desktop-clock enabled; opt desktop-clock-font "Adwaita Sans"; opt clock 24h; opt mainmonitor ""

# Disabled: nothing is started, and a stopped daemon is left alone.
reset; opt desktop-clock disabled
clock apply >/dev/null
assert_not_contains "$(calls)" " open " "disabled: apply opens nothing"
assert_not_contains "$(calls)" " daemon" "disabled: apply starts no daemon"
clock start >/dev/null
assert_not_contains "$(calls)" " open " "disabled: start opens nothing"

# Enabled, default options: the daemon starts and the clock opens as before.
reset; opt desktop-clock enabled
out=$(clock apply)
assert_eq "$out" "" "apply is silent on success"
assert_contains "$(calls)" "--config $cfg/eww daemon" "apply starts the daemon on the config it owns"
assert_contains "$(calls)" "open clock --arg time_fmt=%H:%M" "24 h by default, monitor 0 (no --screen)"
assert_not_contains "$(calls)" "--screen" "no preferred monitor: no --screen"
assert_contains "$(<"$font_scss")" '$clock-font: "Adwaita Sans";' "the default font is rendered"
assert_contains "$(<"$colors_scss")" '$foreground:' "a missing colour partial is rendered before eww parses the stylesheet"

# 12 h follows options/clock.
reset; opt clock 12h; clock apply >/dev/null
assert_contains "$(calls)" "open clock --arg time_fmt=%I:%M %p" "12h: hour, minute and AM/PM"
opt clock 24h

# A running clock is closed, the stylesheet reloaded, then it is reopened.
reset; touch "$state/daemon" "$state/open"; opt desktop-clock-font "Fira Code"
clock apply >/dev/null
assert_eq "$(calls | awk '{print $3}' | tr '\n' ' ')" "ping close reload open " "running: close, reload, open (in that order)"
assert_contains "$(<"$font_scss")" '$clock-font: "Fira Code";' "the font option reaches the partial"
assert_not_contains "$(calls)" " daemon" "running: the daemon is not started twice"

# The font is user text: nothing that SCSS would evaluate or a quote could escape.
for bad in 'x"; color: red' 'a#{b}' 'a\b' "a'b" 'a;b' 'a}b'; do
    reset; opt desktop-clock-font "$bad"
    out=$(clock apply)
    assert_contains "$(<"$font_scss")" '$clock-font: "Adwaita Sans";' "unsafe font $bad falls back to the default"
    assert_contains "$out" "unsafe font" "unsafe font $bad is reported"
done
reset; opt desktop-clock-font ""; clock apply >/dev/null
assert_contains "$(<"$font_scss")" '$clock-font: "Adwaita Sans";' "an empty font falls back to the default"
opt desktop-clock-font "Adwaita Sans"

# Disabling closes the clock and stops the daemon that had nothing else to show.
reset; touch "$state/daemon" "$state/open"; opt desktop-clock disabled
clock apply >/dev/null
assert_contains "$(calls)" "close clock" "disable closes the clock"
assert_contains "$(calls)" "kill" "disable stops the then-idle daemon"
assert_eq "$([ -e "$state/daemon" ] && echo up || echo down)" down "the daemon is gone"
opt desktop-clock enabled

# kill only queues the shutdown; disable returns once the daemon is really gone.
reset; touch "$state/daemon" "$state/open"; opt desktop-clock disabled
STUB_SLOW_KILL=1 clock apply >/dev/null
assert_eq "$([ -e "$state/daemon" ] && echo up || echo down)" down "disable waits for a queued kill to finish"
opt desktop-clock enabled

# A reload eww rejects is reported, not passed off as applied.
reset; touch "$state/daemon" "$state/open"
out=$(STUB_FAIL_RELOAD=1 clock apply); rc=$?
assert_eq "$rc" 1 "apply fails when eww rejects the reload"
assert_contains "$out" "stylesheet does not parse" "apply passes on eww's reason"
reset; touch "$state/daemon" "$state/open"
out=$(STUB_FAIL_RELOAD=1 clock reload); rc=$?
assert_eq "$rc" 1 "reload fails when eww rejects it"

# A daemon that outlives the call must hold neither the caller's pipes (the
# panel waits for them to close) nor the lock (later calls would block).
reset; rm -f "$state/daemon" "$state/open"
if timeout 2 bash -c '"$@" 2>&1 | cat >/dev/null' _ env HOME="$home" XDG_CONFIG_HOME="$cfg" XDG_CACHE_HOME="$cache" \
        STUB_STATE="$state" STUB_LINGER=1 PATH="$bin:$PATH" bash "$cfg/scripts/desktop-clock/desktop-clock.sh" apply; then
    pass "apply returns with its pipes closed while the daemon lives on"
else
    fail "apply holds its caller's pipes through the daemon"
fi
if flock -n "$cache/eww/desktop-clock.lock" true; then
    pass "the lock is free while the daemon lives on"
else
    fail "the daemon holds the owner's lock"
fi

# start is idempotent: an open clock is not reopened.
reset; touch "$state/daemon" "$state/open"
clock start >/dev/null
assert_not_contains "$(calls)" " open " "start leaves an open clock alone"
reset; clock start >/dev/null
assert_contains "$(calls)" " open clock" "start opens a closed clock"

# First login: the overlay has not rendered options/ yet, so the tracked default counts.
reset; rm -f "$cfg/options/desktop-clock"; mkdir -p "$cfg/defaults/options"
printf 'enabled\n' > "$cfg/defaults/options/desktop-clock"
clock start >/dev/null
assert_contains "$(calls)" " open clock" "a missing live option falls back to its tracked default"
printf 'disabled\n' > "$cfg/defaults/options/desktop-clock"; reset; clock start >/dev/null
assert_not_contains "$(calls)" " open " "the fallback is the default's value, not a hard-coded on"
rm -r "$cfg/defaults"; opt desktop-clock enabled

# options/mainmonitor is a connector; eww wants the model.
reset; opt mainmonitor FIX-B; clock apply >/dev/null
assert_contains "$(calls)" "open clock --screen Beta --arg time_fmt=%H:%M" "the main monitor's model is passed to --screen"
reset; opt mainmonitor FIX-GONE; clock apply >/dev/null
assert_not_contains "$(calls)" "--screen" "an unknown connector is never guessed"
reset; opt mainmonitor FIX-C; clock apply >/dev/null
assert_not_contains "$(calls)" "--screen" "two monitors of one model cannot be told apart by name: monitor 0"
reset; opt mainmonitor FIX-B; out=$(STUB_FAIL_SCREEN=1 clock apply); rc=$?
assert_contains "$(calls)" "open clock --arg" "a monitor eww rejects falls back to monitor 0"
assert_eq "$rc:$out" "0:" "...without failing"
opt mainmonitor ""

# Palette reload: only a running, open clock.
reset; clock reload >/dev/null
assert_eq "$(calls | awk '{print $3}' | tr '\n' ' ')" "ping " "reload with no daemon does nothing"
reset; touch "$state/daemon"; clock reload >/dev/null
assert_not_contains "$(calls)" "reload" "reload with the clock closed does nothing"
reset; touch "$state/daemon" "$state/open"; clock reload >/dev/null
assert_contains "$(calls)" " reload" "reload with the clock open reloads"
assert_eq "$([ -e "$state/open" ] && echo open || echo closed)" open "...and never closes it"

# Usage error.
assert_eq "$(clock bogus | head -1 | cut -c1-6)" "usage:" "an unknown subcommand prints usage"

# --- eww/apply_wal_colors.sh -----------------------------------------------

apply() {
    HOME="$home" XDG_CONFIG_HOME="$cfg" XDG_CACHE_HOME="$cache" STUB_STATE="$state" \
        PATH="$bin:$PATH" bash "$cfg/eww/apply_wal_colors.sh" "$@" 2>&1
}

# eww absent: exit 0 and nothing written. A PATH of symlinks to just the tools
# the script needs keeps the real /usr/bin/eww out of reach.
reset; rm -rf "$cache"; mkdir -p "$tmp/min"
for tool in bash mkdir mktemp mv rm cat sed; do ln -sf "$(command -v "$tool")" "$tmp/min/$tool"; done
HOME="$home" XDG_CONFIG_HOME="$cfg" XDG_CACHE_HOME="$cache" PATH="$tmp/min" "$tmp/min/bash" "$cfg/eww/apply_wal_colors.sh"
assert_eq "$?:$([ -e "$cache" ] && echo wrote || echo clean)" "0:clean" "eww not installed: exit 0 and nothing written"

# Fresh HOME, no matugen output: a valid partial from the fallback palette.
reset; rm -rf "$cache"
out=$(apply)
assert_eq "$out" "" "a fresh cache renders silently"
assert_eq "$(<"$colors_scss")" "$(printf '// Generated from the pywal palette by eww/apply_wal_colors.sh - do not edit\n$background: #0e1416;\n$foreground: #dee3e5;')" "the fallback palette's background and foreground"
assert_not_contains "$(calls)" "reload" "no clock running: no reload"

# Idempotent: the same palette neither rewrites nor reloads.
reset; touch "$state/daemon" "$state/open"; stamp=$(stat -c %y "$colors_scss")
sleep 0.01; apply >/dev/null
assert_eq "$(stat -c %y "$colors_scss")" "$stamp" "an unchanged palette leaves the partial alone"
assert_not_contains "$(calls)" "reload" "an unchanged palette does not reload a running clock"

# A new palette recolours the running clock.
mkdir -p "$cache/wal"
for i in {0..15}; do printf '#%02x%02x%02x\n' "$((i * 10))" 20 30; done > "$cache/wal/colors"
reset; touch "$state/daemon" "$state/open"
apply >/dev/null
assert_contains "$(<"$colors_scss")" '$foreground: #46141e;' "the foreground is colour 7 of the new palette"
assert_contains "$(calls)" " reload" "a changed palette reloads the running clock"
reset; touch "$state/daemon" "$state/open"
for i in {0..15}; do printf '#%02x%02x%02x\n' "$((i * 10))" 40 50; done > "$cache/wal/colors"
apply --no-reload >/dev/null
assert_not_contains "$(calls)" "reload" "--no-reload renders without reloading"

# The clock reload must not hold the caller's stderr (wall.sh reads it to EOF).
reset; touch "$state/daemon" "$state/open"
for i in {0..15}; do printf '#%02x%02x%02x\n' "$((i * 10))" 60 70; done > "$cache/wal/colors"
if timeout 10 bash -c 'apply() { HOME="$1" XDG_CONFIG_HOME="$2" XDG_CACHE_HOME="$3" STUB_STATE="$4" PATH="$5:$PATH" bash "$2/eww/apply_wal_colors.sh"; }; apply "$@" 2>&1 | cat >/dev/null' _ "$home" "$cfg" "$cache" "$state" "$bin"; then
    pass "the apply script returns with its stderr closed"
else
    fail "the apply script holds stderr open"
fi

# A failed recolour is reported, and retried by the next run of an unchanged palette.
reset; touch "$state/daemon" "$state/open"
for i in {0..15}; do printf '#%02x%02x%02x\n' "$((i * 10))" 80 90; done > "$cache/wal/colors"
out=$(STUB_FAIL_RELOAD=1 apply 2>&1); rc=$?
assert_eq "$rc" 1 "a rejected reload fails the apply script"
assert_contains "$out" "stylesheet does not parse" "the apply script passes on eww's reason"
reset; touch "$state/daemon" "$state/open"
apply >/dev/null
assert_contains "$(calls)" " reload" "the same palette retries a reload that failed"
reset; touch "$state/daemon" "$state/open"
apply >/dev/null
assert_not_contains "$(calls)" "reload" "once it succeeds, an unchanged palette is left alone again"

# --- tracked files ---------------------------------------------------------

yuck=$(<"$ROOT/eww/eww.yuck")
assert_contains "$yuck" "formattime(EWW_TIME" "the time comes from EWW_TIME, not a polled process"
assert_not_contains "$yuck" "interval \"1s\"" "no polled variable spawns a process per second"
assert_contains "$yuck" "date +'%A - %d/%m'" "the date comes from date, so the weekday follows LC_TIME"
assert_contains "$yuck" ':stacking "bg"' "the clock stays on the background layer"
scss=$(<"$ROOT/eww/eww.scss")
assert_contains "$scss" "eww-colors.scss" "the stylesheet imports the generated colour partial"
assert_contains "$scss" "eww/font.scss" "the stylesheet imports the generated font partial"
assert_contains "$(<"$ROOT/scripts/hyprland/startup.sh")" "desktop-clock.sh\" start" "login starts the clock through its owner script"

test_summary desktop-clock
