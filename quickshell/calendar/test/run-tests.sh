#!/bin/bash
# The calendar card's model under node, then its real QML views offscreen.
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/qml-test.sh
. "$test_dir/../../../scripts/lib/qml-test.sh"
command -v node >/dev/null 2>&1 || { echo 'skip: calendar model tests (node is not installed)'; exit 0; }
TZ=Europe/Rome node "$test_dir/model.mjs"
TZ=Europe/Rome LC_TIME=it_IT.UTF-8 qml_test calendar "$test_dir" "$@"
