#!/bin/bash
# Exercise the update card's model and its real QML view without a compositor.
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/qml-test.sh
. "$test_dir/../../../scripts/lib/qml-test.sh"
command -v node >/dev/null 2>&1 || { echo 'skip: update card model tests (node is not installed)'; exit 0; }
node "$test_dir/model.mjs"
qml_test 'update card' "$test_dir" "$@"
