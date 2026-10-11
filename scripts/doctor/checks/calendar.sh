#!/bin/bash
#
# iCloud calendar sync (scripts/calendar, docs/calendar.md).
#
# Applies only when the tree tracks the timer and an account is stored in the
# keyring; signing in is optional, so no account means no output at all. The
# unit name is the tracked timer's file name, the tools are the packages named
# under install.sh's calendar marker, and the status file is the one sync.sh
# writes (CALENDAR_RUNTIME_DIR overrides it there too). Nothing is restated here.

# _cal_tools <install.sh> — the package names on the line after the calendar
# marker comment, space-separated. Empty when the marker or its line is absent.
_cal_tools() {
    awk '
        { line = $0; sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line) }
        want {
            n = split($0, parts, "\"")
            out = ""
            for (i = 2; i <= n; i += 2) out = out (out == "" ? "" : " ") parts[i]
            print out
            exit
        }
        line == "# Calendar sync (scripts/calendar, docs/calendar.md)" { want = 1 }
    ' "$1" 2>/dev/null
}

_cal_account() { secret-tool lookup service calendar-icloud field username 2>/dev/null || true; }
_cal_timer_enabled() { systemctl --user is-enabled --quiet "$1" 2>/dev/null; }
_cal_have() { command -v "$1" >/dev/null 2>&1; }
_cal_status() { cat "${CALENDAR_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/tmp}/calendar}/status.json" 2>/dev/null || true; }
_cal_now() { date +%s; }

check_calendar() {
    local timer="$DOCTOR_ROOT/scripts/calendar/calendar-sync.timer"
    local installer="$DOCTOR_ROOT/install.sh"
    local unit tools tool status fields state message last found=0
    [ -f "$timer" ] || return 0
    [ -n "$(_cal_account)" ] || return 0
    unit=$(basename "$timer")
    group "Calendar"

    tools=$(_cal_tools "$installer")
    if [ -z "$tools" ]; then
        warn "cannot derive the calendar tools from install.sh" \
            "git -C $(doctor_q "$DOCTOR_ROOT") diff -- $(doctor_q "$installer")"
        found=1
    fi
    for tool in $tools; do
        if ! _cal_have "$tool"; then
            err "$tool is not installed" "sudo pacman -S --needed $tools"
            found=1
        fi
    done
    if ! _cal_timer_enabled "$unit"; then
        warn "$unit is not enabled — the bar and the card only update when the card opens" \
            "bash $(doctor_q "$DOCTOR_ROOT/scripts/calendar/setup.sh")"
        found=1
    fi
    status=$(_cal_status)
    if [ -z "${status//[[:space:]]/}" ]; then
        warn "no sync status yet — the calendar has not synced since login" \
            "bash $(doctor_q "$DOCTOR_ROOT/scripts/calendar/sync.sh")"
        found=1
    else
        # One checked jq call: a non-object, a non-string state or message, or a
        # lastSuccess that is neither null nor a whole number in a sane range
        # yields no fields, so nothing unvalidated reaches the shell arithmetic.
        # The fields are joined with the unit separator, which read does not
        # treat as whitespace, so an empty message keeps its place.
        fields=$(printf '%s' "$status" | jq -r '
            select(type == "object")
            | select((.state // "") | type == "string")
            | select((.message // "") | type == "string")
            | select(.lastSuccess == null or ((.lastSuccess | type) == "number"
                and .lastSuccess == (.lastSuccess | floor)
                and .lastSuccess > -1e15 and .lastSuccess < 1e15))
            | [(.state // ""), (.message // ""), ((.lastSuccess // 0) | tostring)]
            | join("\u001f")' 2>/dev/null) || fields=""
        if [ -z "$fields" ]; then
            warn "status.json is not valid" "bash $(doctor_q "$DOCTOR_ROOT/scripts/calendar/sync.sh")"
            found=1
        else
            IFS=$'\037' read -r state message last <<< "$fields"
            if [ "$state" = failed ]; then
                warn "last sync failed: $message" "bash $(doctor_q "$DOCTOR_ROOT/scripts/calendar/sync.sh")"
                found=1
            elif [ "$last" -le 0 ] || [ $(( $(_cal_now) - last )) -gt 3600 ]; then
                warn "no successful sync in the last hour" "bash $(doctor_q "$DOCTOR_ROOT/scripts/calendar/sync.sh")"
                found=1
            fi
        fi
    fi
    [ "$found" -eq 1 ] || ok "iCloud calendar syncing"
    return 0
}
