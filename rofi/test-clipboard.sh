#!/bin/bash

set -u

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$TEST_DIR/.." && pwd)

# shellcheck source=../scripts/lib/assert.sh
# The shared helper is checked separately by the repository test suite.
# shellcheck disable=SC1091
. "$ROOT/scripts/lib/assert.sh"

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat > "$tmp/bin/rofi" <<'EOF'
#!/usr/bin/env bash
input=$(cat)
{
    printf 'rofi args:'
    printf ' [%s]' "$@"
    printf '\nrofi stdin: [%s]\n' "$input"
} >> "$CLIPBOARD_TEST_LOG"

count=0
[ ! -f "$CLIPBOARD_TEST_COUNT" ] || read -r count < "$CLIPBOARD_TEST_COUNT"
count=$((count + 1))
printf '%s\n' "$count" > "$CLIPBOARD_TEST_COUNT"
printf '%s' "$input" > "$CLIPBOARD_TEST_ROFI_STDIN.$count"
sed -n "${count}p" "$CLIPBOARD_TEST_ANSWERS"
EOF

cat > "$tmp/bin/cliphist" <<'EOF'
#!/usr/bin/env bash
input=$(cat)
{
    printf 'cliphist args:'
    printf ' [%s]' "$@"
    printf '\ncliphist stdin: [%s]\n' "$input"
} >> "$CLIPBOARD_TEST_LOG"

case "${1:-}" in
    list) printf '1\thello\n2\tworld\n' ;;
    decode) printf 'decoded:%s' "$input" ;;
    wipe) exit "${CLIPBOARD_TEST_WIPE_STATUS:-0}" ;;
esac
EOF

cat > "$tmp/bin/wl-copy" <<'EOF'
#!/usr/bin/env bash
input=$(cat)
{
    printf 'wl-copy args:'
    printf ' [%s]' "$@"
    printf '\nwl-copy stdin: [%s]\n' "$input"
} >> "$CLIPBOARD_TEST_LOG"
EOF

cat > "$tmp/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
{
    printf 'notify-send args:'
    printf ' [%s]' "$@"
    printf '\n'
} >> "$CLIPBOARD_TEST_LOG"
EOF

chmod +x "$tmp/bin/rofi" "$tmp/bin/cliphist" "$tmp/bin/wl-copy" "$tmp/bin/notify-send"

export PATH="$tmp/bin:$PATH"
export CLIPBOARD_TEST_LOG="$tmp/log"
export CLIPBOARD_TEST_COUNT="$tmp/count"
export CLIPBOARD_TEST_ANSWERS="$tmp/answers"
export CLIPBOARD_TEST_ROFI_STDIN="$tmp/rofi-stdin"

script_source=$(cat "$TEST_DIR/clipboard.sh")
assignment_lines=$(printf '%s\n' "$script_source" | sed -n '/^\(clear\|yes\|no\)=/p')
assert_eq "$(printf '%s\n' "$assignment_lines" | wc -l)" "3" \
    "the three menu entries are derived from source assignments"
clear=
yes=
no=
eval "$assignment_lines"
clear_entry=$clear
yes_entry=$yes
no_entry=$no

assert_contains "$script_source" '\uf1f8' "the Clear glyph uses a Unicode escape"
assert_contains "$script_source" '\uf058' "the Yes glyph uses a Unicode escape"
assert_contains "$script_source" '\uf52f' "the No glyph uses a Unicode escape"
# U+E000-U+F8FF as UTF-8 bytes, so the check does not depend on the locale;
# grep's status 2 (a broken pattern) must fail rather than pass vacuously.
pua_status=0
printf '%s\n' "$script_source" | LC_ALL=C grep -qP '\xEE[\x80-\xBF]|\xEF[\x80-\xA3]' || pua_status=$?
if [ "$pua_status" -eq 1 ]; then
    pass "the script contains no raw Private Use Area glyphs"
else
    fail "the script contains no raw Private Use Area glyphs"
fi
assert_not_contains "$script_source" "CLIPBOARD_PRINT_CLEAR" \
    "the production script has no test-only menu branch"

run_case() {
    : > "$CLIPBOARD_TEST_LOG"
    rm -f -- "$CLIPBOARD_TEST_COUNT"
    rm -f -- "$CLIPBOARD_TEST_ROFI_STDIN.1" "$CLIPBOARD_TEST_ROFI_STDIN.2"
    printf '%s' "$1" > "$CLIPBOARD_TEST_ANSWERS"
    # The stubs read stdin; never let them inherit the caller's terminal.
    bash "$TEST_DIR/clipboard.sh" </dev/null
}

history_line=$'1\thello'
run_case "$history_line"$'\n'
log=$(cat "$CLIPBOARD_TEST_LOG")
picker_input=$'1\thello\n2\tworld\n'"$clear_entry"
assert_eq "$(cat "$CLIPBOARD_TEST_ROFI_STDIN.1")" "$picker_input" \
    "the picker lists history before the Clear entry"
assert_contains "$log" "rofi args: [-dmenu] [-no-custom] [-p] [Clipboard]" \
    "the picker rejects custom input"
assert_contains "$log" "cliphist args: [decode]" "history selection is decoded"
assert_contains "$log" "cliphist stdin: [$history_line]" "decode receives the exact history line"
assert_contains "$log" "wl-copy args:" "decoded selection is copied"
assert_contains "$log" "wl-copy stdin: [decoded:$history_line]" "wl-copy receives the decoded selection"

run_case "$clear_entry"$'\n'"$yes_entry"$'\n'
log=$(cat "$CLIPBOARD_TEST_LOG")
assert_eq "$(cat "$CLIPBOARD_TEST_ROFI_STDIN.2")" "$no_entry"$'\n'"$yes_entry" \
    "the confirmation lists No before Yes"
assert_contains "$log" "rofi args: [-dmenu] [-no-custom] [-p] [Clear clipboard history?]" \
    "the confirmation rejects custom input"
assert_contains "$log" "cliphist args: [wipe]" "Yes clears clipboard history"
assert_not_contains "$log" "wl-copy args:" "clearing does not copy an entry"

export CLIPBOARD_TEST_WIPE_STATUS=1
run_case "$clear_entry"$'\n'"$yes_entry"$'\n'
unset CLIPBOARD_TEST_WIPE_STATUS
log=$(cat "$CLIPBOARD_TEST_LOG")
assert_contains "$log" "notify-send args: [Clipboard history] [Failed to clear clipboard history]" \
    "a failed wipe sends a notification"

run_case "$clear_entry"$'\n'"$no_entry"$'\n'
log=$(cat "$CLIPBOARD_TEST_LOG")
assert_not_contains "$log" "cliphist args: [wipe]" "No preserves clipboard history"
assert_not_contains "$log" "wl-copy args:" "No does not copy an entry"

run_case "$clear_entry"$'\n\n'
log=$(cat "$CLIPBOARD_TEST_LOG")
assert_not_contains "$log" "cliphist args: [wipe]" "confirmation Escape preserves clipboard history"
assert_not_contains "$log" "wl-copy args:" "confirmation Escape does not copy an entry"

run_case $'\n'
log=$(cat "$CLIPBOARD_TEST_LOG")
assert_contains "$log" "cliphist args: [list]" "opening the picker lists clipboard history"
assert_not_contains "$log" "cliphist args: [decode]" "Escape does not decode an entry"
assert_not_contains "$log" "cliphist args: [wipe]" "Escape does not clear history"
assert_not_contains "$log" "wl-copy args:" "Escape does not copy an entry"

test_summary "clipboard"
