#!/bin/bash
# The calendar card's model under node, then its real QML views offscreen.
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TZ=Europe/Rome node "$test_dir/model.mjs"
runner=/usr/lib/qt6/bin/qmltestrunner
[[ -x $runner ]] || { echo 'Qt 6 declarative test tools are required.' >&2; exit 1; }
compgen -G "$test_dir/tst_*.qml" >/dev/null || exit 0
runtime=$(mktemp -d)
trap 'rm -rf "$runtime"' EXIT
# Keep the application's tracked default font when Qt's theme plugin reads
# the private config, so isolation does not change label/geometry checks.
mkdir -p "$runtime/config/qt6ct"
cp "$test_dir/../../../defaults/qt6ct/qt6ct.conf" "$runtime/config/qt6ct/"
TZ=Europe/Rome LC_TIME=it_IT.UTF-8 QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software HOME="$runtime" XDG_CONFIG_HOME="$runtime/config" \
    XDG_CACHE_HOME="$runtime/cache" XDG_STATE_HOME="$runtime/state" XDG_RUNTIME_DIR="$runtime" \
    "$runner" -input "$test_dir" "$@"
