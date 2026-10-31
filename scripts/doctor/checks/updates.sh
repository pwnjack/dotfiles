#!/bin/bash
#
# One-click system update health (the update card's root helper).
#
# The privileged paths are not repeated here: SUDOERS_FILE and
# INSTALLED_HELPER are parsed from updates/setup-sudo.sh, which owns them, as
# checks/sddm.sh does for its helper.
#
# The feature is optional on a fresh machine, so "not set up" is a WARN with
# the setup command. An installed helper that is not root:root 755, or is a
# symlink, is an ERROR: the NOPASSWD rule makes whatever sits at that path
# root-equivalent. sudo -l is the authority for the grant, not the file.
#
# Hosts without pacman, and trees without the updates/ scripts, get no output:
# the feature does not apply there.

_upd_have_pacman() {
    command -v pacman >/dev/null 2>&1
}

_upd_sudo_listing() {
    sudo -n -l 2>/dev/null
}

# Metadata of the path itself; never -L, so a symlink cannot borrow the
# ownership of what it points at.
_upd_file_state() {
    stat -c '%U:%G %a' -- "$1" 2>/dev/null
}

# Where updates/setup-sudo.sh installs the helper. Normally that script is the
# source of truth and is parsed; this default is used only when the tracked
# sources are gone, so a root helper left behind with nothing to compare it
# against is still noticed. Keep it equal to INSTALLED_HELPER there.
_upd_default_helper() {
    printf '%s' /usr/local/bin/system-update
}

# Whether anything, even a dangling symlink, sits at the path.
_upd_helper_present() {
    [ -e "$1" ] || [ -L "$1" ]
}

# _upd_has_grant <listing> <helper> — the exact no-arguments NOPASSWD entry.
_upd_has_grant() {
    printf '%s\n' "$1" | awk -v command="$2 \"\"" '
        {
            marker = "NOPASSWD: "
            position = index($0, marker)
            if (position == 0) next
            granted = substr($0, position + length(marker))
            count = split(granted, entries, /,/)
            for (i = 1; i <= count; i++) {
                sub(/^[[:space:]]+/, "", entries[i])
                sub(/[[:space:]]+$/, "", entries[i])
                if (entries[i] == "ALL" || entries[i] == command) found = 1
            }
        }
        END { exit !found }
    '
}

check_updates() {
    _upd_have_pacman || return 0

    local setup="$DOCTOR_ROOT/updates/setup-sudo.sh"
    local tracked="$DOCTOR_ROOT/updates/system-update-root.sh"
    local fix sudoers helper listing state found=0

    # A tree without the feature has nothing to check, unless a root helper is
    # still installed: that one stays NOPASSWD-reachable with no source to
    # compare it against.
    if [ ! -e "$setup" ] && [ ! -e "$tracked" ]; then
        helper=$(_upd_default_helper)
        _upd_helper_present "$helper" || return 0
        group "One-click updates"
        warn "installed update helper has no tracked source to check against: $helper" \
            "remove it with: sudo rm -- $(doctor_q "$helper") /etc/sudoers.d/system-update, or restore updates/ from git"
        return 0
    fi
    group "One-click updates"

    if [ ! -f "$setup" ] || [ ! -f "$tracked" ]; then
        err "cannot check one-click updates: updates/setup-sudo.sh or updates/system-update-root.sh is missing" \
            "git -C $(doctor_q "$DOCTOR_ROOT") checkout -- updates/"
        return 0
    fi
    sudoers=$(doctor_assignment "$setup" SUDOERS_FILE)
    helper=$(doctor_assignment "$setup" INSTALLED_HELPER)
    if [ -z "$sudoers" ] || [ -z "$helper" ]; then
        err "cannot derive the update helper paths from updates/setup-sudo.sh" \
            "git -C $(doctor_q "$DOCTOR_ROOT") diff -- updates/setup-sudo.sh"
        return 0
    fi

    fix="bash $(doctor_q "$setup")"
    listing=$(_upd_sudo_listing)
    state=$(_upd_file_state "$helper")

    if [ ! -e "$helper" ] && [ ! -L "$helper" ] && ! _upd_has_grant "$listing" "$helper"; then
        warn "one-click updates are not set up — the update card will ask for the setup" "$fix"
        return 0
    fi

    if [ -L "$helper" ]; then
        err "installed update helper must not be a symlink: $helper" "$fix"
        found=1
    elif [ ! -e "$helper" ]; then
        warn "installed update helper is missing: $helper" "$fix"
        found=1
    elif [ "$state" != "root:root 755" ]; then
        err "installed update helper has unsafe ownership or mode (${state:-unknown}; expected root:root 755)" "$fix"
        found=1
    elif ! cmp -s "$tracked" "$helper"; then
        warn "installed update helper differs from the tracked source" \
            "review $(doctor_q "$tracked"), then run: $fix"
        found=1
    fi

    if ! _upd_has_grant "$listing" "$helper"; then
        warn "$helper is not in the effective passwordless sudo permissions (expected via $sudoers)" "$fix"
        found=1
    fi

    [ "$found" -eq 0 ] && ok "one-click updates are set up"
    return 0
}
