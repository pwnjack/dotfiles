#!/bin/bash
#
# Render this machine's settings: tracked defaults (defaults/) plus this
# machine's overrides (~/.local/state/dotfiles/overrides) become the live files
# every reader uses, after harvesting whatever changed in a live file since the
# last render. See docs/internals/state.md.
#
#   overlay.sh sync [--replace <backup dir>] [<live path>...]
#   overlay.sh check
#
# The config dir is the tree this script lives in. A tree without defaults/ (a
# commit from before the overlay) does nothing, so a hook firing there can never
# record old tracked values as overrides.
set -uo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_dir="$(cd -- "$here/../.." && pwd)"
state_dir="${OVERLAY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles}"
command=${1:-}
shift || true

[ -d "$config_dir/defaults" ] || exit 0
command -v node >/dev/null 2>&1 || { echo "overlay: node is required" >&2; exit 1; }
command -v flock >/dev/null 2>&1 || { echo "overlay: flock is required" >&2; exit 1; }
mkdir -p "$state_dir" || exit 1
exec 9>"$state_dir/overlay.lock"
flock -w 30 9 || { echo "overlay: another sync is still running" >&2; exit 1; }

case "$command" in
    sync)
        node "$here/overlay-cli.mjs" sync "$config_dir" "$state_dir" "$@"
        status=$?
        bash "$here/derived.sh" "$config_dir" || status=1
        exit "$status"
        ;;
    check)
        exec node "$here/overlay-cli.mjs" check "$config_dir" "$state_dir"
        ;;
    *)
        echo "usage: overlay.sh sync [--replace <backup dir>] [<live path>...] | check" >&2
        exit 2
        ;;
esac
