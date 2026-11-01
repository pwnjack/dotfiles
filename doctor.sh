#!/bin/bash
#
# Dotfiles Doctor
# Validates the live Hyprland setup against the tracked configuration.
#
# Usage: ./doctor.sh [--help]
#
# Reports findings at three severities and never modifies anything:
#   ERROR  the session is broken or will break on next login
#   WARN   degraded — a keybind does nothing, a daemon did not start
#   INFO   tidiness — orphaned config, package drift
#
# Exits 1 if any ERROR was found, otherwise 0.
#
# Deliberately NOT `set -e`, unlike install.sh. A check returning non-zero must
# not abort the run: the whole point is to collect every finding and still
# print a summary. Errors are tracked by counter, not by exit status.
set -uo pipefail

DOCTOR_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default to the tree this script lives in, so a clone anywhere works without
# configuration. Overridable so the test suite can point at a fixture.
DOCTOR_ROOT="${DOCTOR_ROOT:-$DOCTOR_SELF_DIR}"
export DOCTOR_ROOT

# Lines 3-13 are the user-facing header; everything below is an implementation
# note that does not belong in --help output.
_doctor_usage() {
    sed -n '3,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
    --help|-h)
        _doctor_usage
        exit 0
        ;;
    "")
        ;;
    *)
        echo "doctor: unknown option '$1'" >&2
        echo >&2
        _doctor_usage >&2
        exit 2
        ;;
esac

# shellcheck source=scripts/doctor/lib.sh
source "$DOCTOR_SELF_DIR/scripts/doctor/lib.sh"

for _doctor_module in symlinks references binaries services sddm updates waybar workspaces hyprctl hardware autostart ssh calendar defaults state plugins themes; do
    # shellcheck source=/dev/null
    source "$DOCTOR_SELF_DIR/scripts/doctor/checks/$_doctor_module.sh"
done
unset _doctor_module

echo "Checking $DOCTOR_ROOT"

# Every check derives its target list from git, so a non-repository root would
# otherwise produce six separately-worded "found nothing" results instead of
# one clear explanation. Bail before any check runs.
if ! doctor_require_repo; then
    summary
    exit 1
fi

check_symlinks
check_references
check_binaries
check_services
check_sddm
check_updates
check_waybar
check_workspaces
check_hyprctl
check_hardware
check_autostart
check_ssh
check_calendar
check_defaults
check_state
check_plugins
check_themes

summary
