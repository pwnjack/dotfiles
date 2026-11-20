#!/bin/bash
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/qml-test.sh
. "$test_dir/../../../scripts/lib/qml-test.sh"
qml_test 'settings panel' "$test_dir" "$@"
command -v node >/dev/null 2>&1 || { echo 'skip: settings panel model tests (node is not installed)'; exit 0; }
node "$test_dir/persist.mjs"
bash "$test_dir/test-request-stdin.sh"
gjs -m "$test_dir/nm-adapter.js"
node "$test_dir/backend.mjs"
node "$test_dir/displays.mjs"
node "$test_dir/monitor-lua.mjs"
node "$test_dir/network.mjs"
node "$test_dir/autostart.mjs"
node "$test_dir/pages.mjs"
node "$test_dir/catalog.mjs"
node "$test_dir/palette.mjs"
node "$test_dir/search.mjs"
node "$test_dir/about.mjs"
node "$test_dir/calendar.mjs"
node "$test_dir/sound.mjs"
node "$test_dir/sound-reader.mjs"
node "$test_dir/controller-contract.mjs"
