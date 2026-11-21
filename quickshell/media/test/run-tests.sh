#!/bin/bash
# Exercise the media card's model.
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
command -v node >/dev/null 2>&1 || { echo 'skip: media card model tests (node is not installed)'; exit 0; }
node "$test_dir/model.mjs"
