#!/bin/bash
#
# Palette fan-out driver.
#
# Every themed component owns an `apply_wal_colors.sh` sitting next to its own
# config. This script discovers them by glob rather than by list, so adding a
# themed component is one new file — no edit here, none in wall.sh, none in
# install.sh. A hand-written list of components would be a second source of
# truth and would drift, exactly as the doctor's checks avoid.
#
# Contract every apply script must honour:
#
#   1. It renders into ~/.cache/wal/ and never writes a tracked file. Tracked
#      files must not change at runtime; the repo tracks only a stable symlink
#      into the cache.
#   2. It always leaves its output file existing, falling back to hardcoded
#      defaults when the palette input is missing. A tracked symlink whose
#      target does not exist is an ERROR in doctor.sh, and on a fresh checkout
#      the cache is empty.
#   3. It is idempotent, and a no-op when its component is not installed.
#   4. Reloading a running consumer is its own job — this driver knows nothing
#      about swaync-client, SIGUSR2, or any other component detail. Anything
#      it leaves running in the background must not keep stderr open:
#      wall.sh reads stderr to the end to name failed components, so a held
#      stderr stalls every wallpaper change until that process exits.
#
# Scripts run sequentially. They are cheap, and serial output keeps a failure
# attributable to the component that caused it.
#
# All components are attempted; a nonzero exit reports partial failure.
# Callers decide whether that failure should abort their own operation.
#

set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"

# Without nullglob an unmatched pattern is passed through literally and the
# loop would try to execute a path named "*/apply_wal_colors.sh".
shopt -s nullglob

failed=0
for script in "$config_dir"/*/apply_wal_colors.sh; do
    [ -x "$script" ] || continue
    if ! "$script"; then
        echo "apply-wal: ${script#"$config_dir"/} failed" >&2
        failed=$((failed + 1))
    fi
done

[ "$failed" -eq 0 ] || echo "apply-wal: $failed component(s) failed" >&2
[ "$failed" -eq 0 ]
