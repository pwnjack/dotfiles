#!/bin/bash
#
# Tests for scripts/hyprland/screenshot.sh. hyprshot, swappy, sleep and
# hyprctl are fakes on PATH that append to one event log, so the order of
# delay and capture is visible and no real screenshot is ever taken.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# screenshot.sh runs from a copy of the tree, so its read-text.sh is the
# stand-in below: it logs what the capture pipes to it, and reads nothing real.
SHOT="$TMP/tree/hyprland/screenshot.sh"
mkdir -p "$TMP/tree/hyprland" "$TMP/tree/capture"
cp "$TEST_DIR/screenshot.sh" "$SHOT"
ln -s "$TEST_DIR/../capture/toast.sh" "$TMP/tree/capture/toast.sh"
cat > "$TMP/tree/capture/read-text.sh" <<'EOF'
#!/bin/bash
printf 'read-text stdin=%s\n' "$(cat)" >> "$EVENTS"
EOF
chmod +x "$TMP/tree/capture/read-text.sh"

# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

mkdir -p "$TMP/bin" "$TMP/home/.config/options"
export EVENTS="$TMP/events"
cat > "$TMP/bin/hyprshot" <<'EOF'
#!/bin/bash
printf 'hyprshot %s\n' "$*" >> "$EVENTS"
[[ " $* " == *" --raw "* ]] && printf 'PNG'
# A save writes -o/-f, unless the test cancels the selection.
out="" name=""
while [ $# -gt 0 ]; do
    case $1 in -o) out=$2; shift ;; -f) name=$2; shift ;; esac
    shift
done
[ -n "$name" ] && [ -z "${SHOT_CANCEL:-}" ] && mkdir -p "$out" && printf 'PNG' > "$out/$name"
exit 0
EOF
cat > "$TMP/bin/notify-send" <<'EOF'
#!/bin/bash
printf 'notify %s\n' "$*" >> "$EVENTS.notify"
EOF
cat > "$TMP/bin/swappy" <<'EOF'
#!/bin/bash
printf 'swappy %s stdin=%s\n' "$*" "$(cat)" >> "$EVENTS"
EOF
cat > "$TMP/bin/sleep" <<'EOF'
#!/bin/bash
printf 'sleep %s\n' "$*" >> "$EVENTS"
EOF
cat > "$TMP/bin/hyprctl" <<'EOF'
#!/bin/bash
[ "$*" = 'monitors -j' ] && echo '[{"name":"TEST-2","focused":false},{"name":"TEST-1","focused":true}]'
EOF
chmod +x "$TMP/bin/"*

shot() {
    : > "$EVENTS"
    HOME="$TMP/home" PATH="$TMP/bin:$PATH" bash "$SHOT" "$@"
}
freeze() { printf '%s\n' "$1" > "$TMP/home/.config/options/capture-freeze"; }

freeze false
shot region
if [[ $(cat "$EVENTS") =~ ^hyprshot\ -m\ region\ -s\ -o\ $TMP/home/Pictures/Screenshots\ -f\ Screenshot_[0-9-]+_[0-9:]+\.png$ ]]; then
    pass "region writes to ~/Pictures/Screenshots"
else
    fail "region argv" "$(cat "$EVENTS")"
fi

# The toast is detached; give it a moment to log. The real sleep, not the fake.
toast_log() {
    local _
    for _ in $(seq 50); do [ -s "$EVENTS.notify" ] && break; /usr/bin/sleep 0.05; done
    cat "$EVENTS.notify" 2>/dev/null
}
assert_contains "$(toast_log)" "Screenshot saved" "a saved shot gets the shared toast"
assert_contains "$(cat "$EVENTS.notify")" "Show in folder" "the toast offers Show in folder"
rm -f "$EVENTS.notify"
rm -rf "$TMP/home/Pictures/Screenshots"   # same-second names would collide
SHOT_CANCEL=1 shot region
/usr/bin/sleep 0.3
assert_eq "$(cat "$EVENTS.notify" 2>/dev/null)" "" "a cancelled selection gets no toast"

freeze true
shot region
assert_contains "$(cat "$EVENTS")" " -z" "capture-freeze true freezes"

freeze false
old=screenshot   # the pre-rename option file
printf 'true\n' > "$TMP/home/.config/options/$old"
shot region
case "$(cat "$EVENTS")" in *" -z"*) fail "the pre-rename option file is ignored" ;; *) pass "the pre-rename option file is ignored" ;; esac

shot screen
assert_contains "$(cat "$EVENTS")" "hyprshot -m output -m TEST-1 " "screen is the focused monitor"
freeze true
shot screen
case "$(cat "$EVENTS")" in *" -z"*) fail "screen never freezes" ;; *) pass "screen never freezes" ;; esac
freeze false
shot region --delay 08
assert_eq "$(head -n1 "$EVENTS")" "sleep 8" "a zero-padded delay is decimal"
shot region --delay 0
case "$(cat "$EVENTS")" in sleep*) fail "delay 0 does not sleep" ;; *) pass "delay 0 does not sleep" ;; esac
shot window
assert_contains "$(cat "$EVENTS")" "hyprshot -m window " "window target"

shot region --annotate
assert_eq "$(cat "$EVENTS")" $'hyprshot -m region --raw\nswappy -f - stdin=PNG' "annotate pipes the raw PNG to swappy"

shot screen --annotate --delay 3
assert_eq "$(head -n1 "$EVENTS")" "sleep 3" "the delay runs first"
assert_contains "$(sed -n 2p "$EVENTS")" "hyprshot -m output -m TEST-1 --raw" "then the capture"

shot region --text
assert_eq "$(cat "$EVENTS")" $'hyprshot -m region --raw\nread-text stdin=PNG' "text pipes the raw PNG to read-text.sh"
freeze true
shot region --text --delay 2
assert_eq "$(head -n1 "$EVENTS")" "sleep 2" "text honours the delay"
assert_contains "$(sed -n 2p "$EVENTS")" "hyprshot -m region -z --raw" "text honours capture-freeze"
freeze false
shot screen --text
assert_contains "$(cat "$EVENTS")" "hyprshot -m output -m TEST-1 --raw" "text works on a screen"

shot region
case "$(cat "$EVENTS")" in sleep*) fail "no delay by default" ;; *) pass "no delay by default" ;; esac

for bad in "bogus" "output" "region --delay x" "region --frobnicate" "region --text --annotate" "region --annotate --text"; do
    # shellcheck disable=SC2086
    shot $bad 2>/dev/null; rc=$?
    assert_eq "$rc" 2 "usage error: $bad"
done

test_summary screenshot
