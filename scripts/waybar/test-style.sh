#!/bin/bash
#
# Tests for waybar/style.css.
#
# Since Waybar 0.16 a custom module's hover state is set on an unnamed box
# around the label that carries #custom-<name>, so `#custom-x:hover` matches
# nothing and the module silently loses its hover pill. A custom module must
# be matched through that parent: `box:hover > #custom-x`.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STYLE="$TEST_DIR/../../waybar/style.css"

# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

echo "style.css"

direct=$(grep -nE '#custom-[a-z-]+(\.[a-z-]+)*:hover' "$STYLE" || true)
assert_eq "$direct" "" "no custom module is matched by its own :hover"
through=$(grep -cE '^box:hover > #custom-[a-z-]+' "$STYLE" || true)
if [ "$through" -gt 0 ]; then pass "custom modules are matched through their hovered box ($through)"
else fail "custom modules are matched through their hovered box" "found none"; fi

test_summary "style.css"
