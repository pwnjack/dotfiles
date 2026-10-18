#!/bin/bash
# Exercise the sound popover's model and its real QML views without a compositor.
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
for binary in node mktemp mkdir cp; do
    command -v "$binary" >/dev/null 2>&1 || { echo "$binary is required for the sound popover tests." >&2; exit 1; }
done
node "$test_dir/model.mjs"
# The views arrive with their own tst_*.qml files; until then there is no QML half.
compgen -G "$test_dir/tst_*.qml" > /dev/null || exit 0
runner=/usr/lib/qt6/bin/qmltestrunner
[[ -x $runner ]] || { echo 'Qt 6 declarative test tools are required.' >&2; exit 1; }
runtime=$(mktemp -d)
trap 'rm -rf "$runtime"' EXIT
# Keep the application's tracked default font when Qt's theme plugin reads
# the private config, so isolation does not change label/geometry checks.
mkdir -p "$runtime/config/qt6ct"
cp "$test_dir/../../../defaults/qt6ct/qt6ct.conf" "$runtime/config/qt6ct/"
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software HOME="$runtime" XDG_CONFIG_HOME="$runtime/config" \
    XDG_CACHE_HOME="$runtime/cache" XDG_STATE_HOME="$runtime/state" XDG_RUNTIME_DIR="$runtime" \
    "$runner" -input "$test_dir" "$@"
