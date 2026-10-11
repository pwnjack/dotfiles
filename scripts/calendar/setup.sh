#!/bin/bash
# iCloud calendar account wiring (docs/calendar.md).
#   setup.sh                    install.sh's call: never prompts. With an account
#                               stored, links and enables the sync timer.
#   setup.sh --sign-in [--stdin] ask (or read two lines: Apple ID, app-specific
#                               password), store them in the keyring, check them
#                               with a discover, record read-only calendars,
#                               enable the timer, sync once.
#   setup.sh --sign-out         forget the account and the local copy.
# The password only ever travels through stdin: secret-tool store reads it,
# vdirsyncer and curl fetch it themselves.
# shellcheck disable=SC2154  # cal_* paths come from lib.sh
set -euo pipefail
# shellcheck source=scripts/calendar/lib.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
units=(calendar-sync.service calendar-sync.timer)

store() { printf '%s\n' "$2" | secret-tool store --label="Calendar (iCloud) $1" service calendar-icloud field "$1"; }
forget() {
    secret-tool clear service calendar-icloud field username 2>/dev/null || true
    secret-tool clear service calendar-icloud field password 2>/dev/null || true
}
# keyring_empty — true when neither field is left; clear exits 1 when nothing
# matched, so forget cannot tell a removal from a failure on its own.
keyring_empty() { [[ -z $(cal_secret username) && -z $(cal_secret password) ]]; }
enable_timer() {
    local unit
    for unit in "${units[@]}"; do systemctl --user link "$cal_dir/$unit" >/dev/null; done
    systemctl --user enable --now calendar-sync.timer >/dev/null
}

case ${1:-} in
    '')
        if [[ -z $(cal_account) ]]; then
            echo 'Calendar: no iCloud account yet; sign in from Settings › Calendar (or scripts/calendar/setup.sh --sign-in).'
            exit 0
        fi
        enable_timer
        ;;
    --sign-in)
        if [[ ${2:-} == --stdin ]]; then
            IFS= read -r id || true
            IFS= read -r pw || true
        else
            read -r -p 'Apple ID: ' id
            read -r -s -p 'App-specific password: ' pw; echo
        fi
        [[ -n ${id:-} && -n ${pw:-} ]] || { echo 'Both the Apple ID and the app-specific password are needed.' >&2; exit 1; }
        if ! store username "$id" || ! store password "$pw"; then
            forget
            echo 'Could not store the account in the keyring' >&2
            exit 1
        fi
        unset pw
        # discover asks before creating each local folder; the answer is always yes.
        if ! out=$(vdirsyncer discover icloud < <(yes 2>/dev/null) 2>&1); then
            forget
            if grep -qiE '401|unauthori[sz]ed' <<<"$out"; then
                echo 'Sign-in rejected: check the Apple ID and the app-specific password.' >&2
            else
                echo "Could not reach iCloud: $(tail -n1 <<<"$out")" >&2
            fi
            exit 1
        fi
        mkdir -p "$cal_state"; touch "$cal_state/discovered"
        bash "$cal_dir/writable.sh" || echo 'Could not check which calendars are read-only; all are offered.' >&2
        enable_timer
        bash "$cal_dir/sync.sh"
        ;;
    --sign-out)
        systemctl --user disable --now calendar-sync.timer >/dev/null 2>&1 || true
        forget
        rm -rf -- "$cal_data" "$cal_state" "${CALENDAR_VDIR_STATUS:-${XDG_STATE_HOME:-$HOME/.local/state}/vdirsyncer/status}"
        rm -f -- "$cal_runtime/agenda.json" "$cal_runtime/status.json"
        pkill -RTMIN+12 waybar 2>/dev/null || true
        # Cleanup runs first, so a keyring that refuses the clear still leaves
        # no local copy behind; the failure is reported last.
        if ! keyring_empty; then
            echo 'Could not remove the account from the keyring' >&2
            exit 1
        fi
        ;;
    *) echo 'Usage: setup.sh [--sign-in [--stdin] | --sign-out]' >&2; exit 2 ;;
esac
