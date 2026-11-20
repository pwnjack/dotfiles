#!/bin/bash
# Exercise the real QML UI without taking desktop focus or applying wallpapers.
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/qml-test.sh
. "$test_dir/../../../scripts/lib/qml-test.sh"
qml_test 'wallpaper carousel' "$test_dir" "$@"
