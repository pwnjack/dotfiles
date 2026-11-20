#!/bin/bash
# Exercise the overlay's model and its real QML view without a compositor.
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_dir="$test_dir/../../.."
# shellcheck source=scripts/lib/options.sh
. "$config_dir/scripts/lib/options.sh"
# shellcheck source=scripts/lib/qml-test.sh
. "$config_dir/scripts/lib/qml-test.sh"
command -v node >/dev/null 2>&1 || { echo 'skip: keybinds overlay model tests (node is not installed)'; exit 0; }
node "$test_dir/sheet.mjs"
# QML reads real-sheet.json by relative URL. A private copy preserves that
# layout without sharing the generated file with test/test-docs.sh, which also
# invokes this suite. Production QML is copied fresh on every invocation.
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/test"
cp "$test_dir/../"*.qml "$stage/"
cp "$test_dir/../sheet.mjs" "$stage/"
cp "$test_dir/"tst_*.qml "$stage/test/"
# The tracked default font: options/ is this machine's rendered copy and is not in a commit.
font=$(option "$config_dir/defaults/options/font")
[[ -n $font ]] || { echo 'defaults/options/font is missing or empty.' >&2; exit 1; }
"$config_dir/scripts/keybinds/keybinds-sheet.sh" --json \
    | jq --arg font "$font" '{font: $font, sections}' > "$stage/test/real-sheet.json"
QML_XHR_ALLOW_FILE_READ=1 qml_test 'keybinds overlay' "$stage/test" "$@"
