#!/bin/bash
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
runtime=$(mktemp -d)
trap 'rm -rf "$runtime"' EXIT
# Keep the application's tracked default font when Qt's theme plugin reads
# the private config, so isolation does not change label/geometry checks.
mkdir -p "$runtime/config/qt6ct"
cp "$test_dir/../../../defaults/qt6ct/qt6ct.conf" "$runtime/config/qt6ct/"
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software HOME="$runtime" XDG_CONFIG_HOME="$runtime/config" \
    XDG_CACHE_HOME="$runtime/cache" XDG_STATE_HOME="$runtime/state" XDG_RUNTIME_DIR="$runtime" \
    /usr/lib/qt6/bin/qmltestrunner -input "$test_dir" "$@"
bash "$test_dir/test-persist.sh"
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
