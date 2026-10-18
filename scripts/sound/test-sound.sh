#!/bin/bash
# Tests for scripts/sound/sound.sh against stand-in pactl and pw-metadata binaries.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOUND="$TEST_DIR/sound.sh"
FIX="$TEST_DIR/fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck disable=SC1091 # Shared assertions are checked by their own suite.
# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

# pactl logs its argv and answers the two listings from canned JSON.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/pactl" <<'STUB'
#!/bin/sh
echo "$*" >> "$PACTL_LOG"
case "$*" in
    "-f json list sink-inputs") echo '[{"index":37},{"index":41}]' ;;
    "-f json list sinks") echo '[{"name":"alsa_output.pci-0000_00_1f.3.analog-stereo"},{"name":"effect_input.virtual_surround"}]' ;;
esac
STUB
# pw-metadata serves the dump in $PWM_DUMP, or the monitor stream in $PWM_MONITOR with -m.
cat > "$TMP/bin/pw-metadata" <<'STUB'
#!/bin/sh
case "$*" in
    "-n default -m") cat "$PWM_MONITOR" ;;
    "-n default") cat "$PWM_DUMP" ;;
    *) exit 2 ;;
esac
STUB
chmod +x "$TMP/bin/pactl" "$TMP/bin/pw-metadata"
export PACTL_LOG="$TMP/pactl.log"
export SOUND_PACTL="$TMP/bin/pactl" SOUND_PW_METADATA="$TMP/bin/pw-metadata"
run() { bash "$SOUND" "$@"; }
moves() { grep '^move-sink-input' "$PACTL_LOG" 2>/dev/null || true; }

echo "sound.sh"

: > "$PACTL_LOG"
out=$(run route 37 alsa_output.pci-0000_00_1f.3.analog-stereo); rc=$?
assert_eq "$rc" 0 "route to a sink succeeds"
assert_eq "$out" '{"ok":true}' "route reports ok"
assert_eq "$(moves)" "move-sink-input 37 alsa_output.pci-0000_00_1f.3.analog-stereo" "route moves the stream to the named sink"

: > "$PACTL_LOG"
out=$(run route 37 default)
assert_eq "$out" '{"ok":true}' "route to default reports ok"
assert_eq "$(moves)" 'move-sink-input 37 @DEFAULT_SINK@' "route default un-pins to the default sink"

: > "$PACTL_LOG"
out=$(run route 99 alsa_output.pci-0000_00_1f.3.analog-stereo); rc=$?
assert_eq "$rc" 1 "an unknown stream fails"
assert_eq "$(jq -r .error <<<"$out")" "No such stream: 99" "the unknown stream is named"
assert_eq "$(moves)" "" "an unknown stream is never moved"

: > "$PACTL_LOG"
out=$(run route 'x;1' default); rc=$?
assert_eq "$rc" 1 "a non-numeric serial fails"
assert_eq "$(jq -r .error <<<"$out")" "No such stream: x;1" "a hostile serial is echoed as valid JSON"
assert_eq "$(moves)" "" "a non-numeric serial is never moved"

: > "$PACTL_LOG"
out=$(run route 37 'bad name;'); rc=$?
assert_eq "$rc" 1 "a malformed sink name fails"
assert_eq "$(jq -r .error <<<"$out")" "No such output: bad name;" "the malformed sink is named"
assert_eq "$(moves)" "" "a malformed sink name is never moved"

: > "$PACTL_LOG"
out=$(run route 37 alsa_output.gone); rc=$?
assert_eq "$rc" 1 "a well-formed but absent sink fails"
assert_eq "$(jq -r .error <<<"$out")" "No such output: alsa_output.gone" "the absent sink is named"
assert_eq "$(moves)" "" "an absent sink is never moved"

export PWM_DUMP="$FIX/pw-metadata-pinned.txt" PWM_MONITOR="$FIX/pw-metadata-watch.txt"
assert_eq "$(run pins)" '{"107":"236"}' "pins reads the pinned target by object id"
PWM_DUMP="$FIX/pw-metadata-unpinned.txt"
assert_eq "$(run pins)" '{}' "-1 is unpinned and left out"

PWM_DUMP="$FIX/pw-metadata-unpinned.txt"
assert_eq "$(run pins --watch | tr '\n' ' ')" '{} {"107":"236"} {} ' "watch prints the start state, then each change"
PWM_DUMP="$FIX/pw-metadata-pinned.txt"
assert_eq "$(run pins --watch | tr '\n' ' ')" '{"107":"236"} {} ' "watch starts from a pin already present and ignores repeats"

out=$(run frobnicate 2>&1); rc=$?
assert_eq "$rc" 2 "an unknown subcommand exits 2"
assert_contains "$out" "usage:" "an unknown subcommand prints usage"
run route 37 >/dev/null 2>&1; assert_eq "$?" 2 "route without a sink exits 2"

out=$(SOUND_PACTL=/nonexistent run route 1 default); rc=$?
assert_eq "$rc" 1 "a missing pactl fails"
assert_eq "$(jq -r .error <<<"$out")" "pactl is required" "a missing pactl is named"
out=$(SOUND_PW_METADATA=/nonexistent run pins); rc=$?
assert_eq "$rc" 1 "a missing pw-metadata fails"
assert_eq "$(jq -r .error <<<"$out")" "pw-metadata is required" "a missing pw-metadata is named"

test_summary
