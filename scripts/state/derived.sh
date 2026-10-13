#!/bin/bash
#
# Files derived from options, rendered after every overlay sync (overlay.sh
# runs this inside its lock): each step writes only into ~/.local/state, where
# a tracked symlink points, and always leaves its output existing.
#
#   derived.sh <config dir>
set -uo pipefail
# shellcheck disable=SC2034 # used by the steps added to this file
config_dir=${1:?usage: derived.sh <config dir>}
status=0
exit "$status"
