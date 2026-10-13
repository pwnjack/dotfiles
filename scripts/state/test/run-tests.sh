#!/bin/bash
# The machine-state overlay: the pure engine, then the CLI and its shell entry.
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
node "$test_dir/overlay.mjs"
for suite in "$test_dir"/test-*.sh; do
    [ -e "$suite" ] || continue
    bash "$suite"
done
