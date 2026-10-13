#!/bin/bash
# Exercise the overlay's model and its real QML view without a compositor.
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
node "$test_dir/sheet.mjs"
runner=/usr/lib/qt6/bin/qmltestrunner
[[ -x $runner ]] || { echo 'Qt 6 declarative test tools are required.' >&2; exit 1; }
runtime=$(mktemp -d)
# The real sheet, rendered for this run, so tst_Overlay can check that no label
# in keybinds.lua is elided. It sits beside the test because a QML test can read
# a file by relative URL but not an environment variable.
real_sheet="$test_dir/real-sheet.json"
trap 'rmdir "$runtime"; rm -f "$real_sheet"' EXIT
config_dir="$test_dir/../../.."
# The tracked default font: options/ is this machine's rendered copy and is not in a commit.
font=$(head -n1 "$config_dir/defaults/options/font" 2>/dev/null)
[[ -n $font ]] || { echo 'defaults/options/font is missing or empty.' >&2; exit 1; }
"$config_dir/scripts/keybinds/keybinds-sheet.sh" --json \
    | jq --arg font "$font" '{font: $font, sections}' > "$real_sheet"
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software XDG_RUNTIME_DIR="$runtime" QML_XHR_ALLOW_FILE_READ=1 \
    "$runner" -input "$test_dir" "$@"
