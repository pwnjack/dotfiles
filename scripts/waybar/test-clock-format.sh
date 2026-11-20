#!/bin/bash
set -uo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
script="$TEST_DIR/clock-format.sh"
# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
run() { CLOCK_OPTION="$tmp/clock" CLOCK_INCLUDE="$tmp/out/clock.jsonc" bash "$script" --no-reload; cat "$tmp/out/clock.jsonc"; }
assert_eq "$(run)" '{ "clock": { "format": "{:L%a %d  <b>%H:%M</b>}" } }' 'missing option renders 24 h'
printf '12h\n' > "$tmp/clock"
assert_eq "$(run)" '{ "clock": { "format": "{:L%a %d  <b>%I:%M %p</b>}" } }' '12h renders the 12-hour format'
printf 'banana\n' > "$tmp/clock"
assert_eq "$(run)" '{ "clock": { "format": "{:L%a %d  <b>%H:%M</b>}" } }' 'anything else falls back to 24 h'
printf 'enabled\n' > "$tmp/clock-seconds"
assert_eq "$(run)" '{ "clock": { "format": "{:L%a %d  <b>%H:%M:%S</b>}", "interval": 1 } }' 'seconds render in 24 h with a one-second interval'
printf '12h\n' > "$tmp/clock"
assert_eq "$(run)" '{ "clock": { "format": "{:L%a %d  <b>%I:%M:%S %p</b>}", "interval": 1 } }' 'seconds render in 12 h with a one-second interval'
printf 'banana\n' > "$tmp/clock-seconds"; printf '24h\n' > "$tmp/clock"
assert_eq "$(run)" '{ "clock": { "format": "{:L%a %d  <b>%H:%M</b>}" } }' 'anything but enabled leaves seconds off'
rm -f "$tmp/clock-seconds"
assert_eq "$(find "$tmp/out" -name 'clock.jsonc.*')" '' 'no temporary file is left behind'

# The reload path: pkill runs exactly when --no-reload is absent.
mkdir -p "$tmp/bin"
printf '#!/bin/bash\necho "$*" >> "%s/pkill.log"\n' "$tmp" > "$tmp/bin/pkill"
# A running bar, and a busctl that registers nothing, so the reload through
# waybar.sh never reaches the real session's tray.
printf '#!/bin/bash\nexit "${PGREP_STATUS:-0}"\n' > "$tmp/bin/pgrep"
printf '#!/bin/bash\nexit 0\n' > "$tmp/bin/busctl"
chmod +x "$tmp/bin/pkill" "$tmp/bin/pgrep" "$tmp/bin/busctl"
PATH="$tmp/bin:$PATH" CLOCK_OPTION="$tmp/clock" CLOCK_INCLUDE="$tmp/out/clock.jsonc" bash "$script" --no-reload
[[ ! -e $tmp/pkill.log ]]
check '--no-reload does not signal Waybar'
PATH="$tmp/bin:$PATH" CLOCK_OPTION="$tmp/clock" CLOCK_INCLUDE="$tmp/out/clock.jsonc" bash "$script"
assert_eq "$(<"$tmp/pkill.log")" '-USR2 -x waybar' 'a render signals Waybar once'
rm -f "$tmp/pkill.log"
PGREP_STATUS=1 PATH="$tmp/bin:$PATH" CLOCK_OPTION="$tmp/clock" CLOCK_INCLUDE="$tmp/out/clock.jsonc" bash "$script"
[[ ! -e $tmp/pkill.log ]]
check 'a stopped bar is neither started nor signalled'

# The main config must not set clock.format (it would win over the include key by
# key), and its include must be the path this script writes by default.
config="$(dirname "$script")/../../waybar/config.jsonc"
clock_block=$(sed -n '/^  "clock": {/,/^  },/p' "$config")
! grep -Eq '^    "(format|interval)":' <<< "$clock_block"
check 'waybar/config.jsonc sets neither clock.format nor clock.interval'
grep -Fq '"include": ["~/.local/state/waybar/clock.jsonc"' "$config"
check 'waybar/config.jsonc includes ~/.local/state/waybar/clock.jsonc'
# shellcheck disable=SC2016 # the literal $HOME text is what is being checked
grep -Fq 'include=${CLOCK_INCLUDE:-$HOME/.local/state/waybar/clock.jsonc}' "$script"
check 'clock-format.sh defaults to the include config.jsonc names'
test_summary clock-format
