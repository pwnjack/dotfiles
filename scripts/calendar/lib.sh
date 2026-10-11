#!/bin/bash
# Paths and keyring lookups shared by the calendar scripts. Sourced, never run.
# Every path has an override so the suites run against a throwaway tree.
# shellcheck disable=SC2034  # read by the scripts that source this
cal_runtime=${CALENDAR_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/tmp}/calendar}
cal_state=${CALENDAR_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/calendar}
cal_data=${CALENDAR_DATA:-$HOME/.local/share/calendars/icloud}
cal_options=${CALENDAR_OPTIONS:-$HOME/.config/options}
cal_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# cal_secret <field> — username or password from the keyring; empty when absent.
cal_secret() { secret-tool lookup service calendar-icloud field "$1" 2>/dev/null || true; }
cal_account() { cal_secret username; }

# cal_hidden — calendar names hidden from the bar and the card, one per line.
cal_hidden() {
    [[ -r $cal_options/calendar-hidden ]] || return 0
    grep -v '^[[:space:]]*$' "$cal_options/calendar-hidden" || true
}

# cal_skipped — collections that hold no events (reminder lists), one name per
# line; written by writable.sh.
cal_skipped() {
    [[ -r $cal_state/skip ]] || return 0
    grep -v '^[[:space:]]*$' "$cal_state/skip" || true
}

# cal_excluded — every name khal must leave out: hidden, then skipped.
cal_excluded() { cal_hidden; cal_skipped; }
