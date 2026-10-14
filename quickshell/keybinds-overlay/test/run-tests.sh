#!/bin/bash
# Exercise the overlay's model and its real QML view without a compositor.
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
node "$test_dir/sheet.mjs"
runner=/usr/lib/qt6/bin/qmltestrunner
[[ -x $runner ]] || { echo 'Qt 6 declarative test tools are required.' >&2; exit 1; }
runtime=$(mktemp -d)
trap 'rm -rf "$runtime"' EXIT
# Keep the application's tracked default font when Qt's theme plugin reads
# the private config, so isolation does not change label/geometry checks.
mkdir -p "$runtime/config/qt6ct"
cp "$test_dir/../../../defaults/qt6ct/qt6ct.conf" "$runtime/config/qt6ct/"
# QML reads real-sheet.json by relative URL. A private copy preserves that
# layout without sharing the generated file with test/test-docs.sh, which also
# invokes this suite. Production QML is copied fresh on every invocation.
mkdir -p "$runtime/test"
cp "$test_dir/../"*.qml "$runtime/"
cp "$test_dir/../sheet.mjs" "$runtime/"
cp "$test_dir/"tst_*.qml "$runtime/test/"
real_sheet="$runtime/test/real-sheet.json"
config_dir="$test_dir/../../.."
# The tracked default font: options/ is this machine's rendered copy and is not in a commit.
font=$(head -n1 "$config_dir/defaults/options/font" 2>/dev/null)
[[ -n $font ]] || { echo 'defaults/options/font is missing or empty.' >&2; exit 1; }
"$config_dir/scripts/keybinds/keybinds-sheet.sh" --json \
    | jq --arg font "$font" '{font: $font, sections}' > "$real_sheet"
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software HOME="$runtime" XDG_CONFIG_HOME="$runtime/config" \
    XDG_CACHE_HOME="$runtime/cache" XDG_STATE_HOME="$runtime/state" XDG_RUNTIME_DIR="$runtime" QML_XHR_ALLOW_FILE_READ=1 \
    "$runner" -input "$runtime/test" "$@"
