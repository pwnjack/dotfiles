#!/bin/bash
#
# SDDM greeter wallpaper sync health.
#
# The privileged targets are not repeated here. The sudoers drop-in and
# installed-helper paths come from setup-sudo.sh, which owns their definitions;
# the default theme is parsed from the tracked root-helper source for the same
# reason. Changing any of them therefore changes setup and diagnosis together.
#
# This check is intentionally absent on hosts whose display manager is not
# SDDM. The dotfiles can be used elsewhere, and a dormant SDDM directory there
# is configuration material rather than a broken live service.
#
# SUDO -L IS THE AUTHORITY FOR THE GRANT. Merely finding a sudoers file cannot
# prove that sudo parsed it, that a later rule did not alter the result, or that
# it belongs to this user. The effective non-interactive listing is the same
# boundary the watcher depends on.

# Host filesystem seams let the dependency-free tests exercise real parsing
# and mtime comparisons without reading or writing the machine's /etc, /usr or
# cache. They default to the live paths in an ordinary doctor run.
DOCTOR_SDDM_CONF="${DOCTOR_SDDM_CONF:-/etc/sddm.conf}"
DOCTOR_SDDM_THEMES="${DOCTOR_SDDM_THEMES:-/usr/share/sddm/themes}"
DOCTOR_SDDM_AWWW_CACHE="${DOCTOR_SDDM_AWWW_CACHE:-$HOME/.cache/awww}"

# Each host probe is isolated so tests can replace host state without replacing
# the check's decisions.
_sddm_is_display_manager() {
    local unit

    if [ -n "${DOCTOR_SDDM_DISPLAY_MANAGER:-}" ]; then
        [ "$DOCTOR_SDDM_DISPLAY_MANAGER" = "sddm" ]
        return
    fi

    unit=$(systemctl show -p Id --value display-manager.service 2>/dev/null)
    if [ -n "$unit" ]; then
        [ "$unit" = "sddm.service" ]
        return
    fi

    # systemctl cannot reach the system bus from some containers and sandboxes,
    # while the systemd display-manager symlink remains readable and canonical.
    unit=$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)
    [ "${unit##*/}" = "sddm.service" ]
}

_sddm_sudo_listing() {
    sudo -n -l 2>/dev/null
}

_sddm_watcher_running() {
    pgrep -f -- "$DOCTOR_ROOT/sddm/watch_wallpaper.sh" >/dev/null 2>&1
}

_sddm_have_ffmpeg() {
    command -v ffmpeg >/dev/null 2>&1
}

_sddm_username() {
    id -un 2>/dev/null
}

# Metadata is a host probe of its own because the test fixture cannot create
# root-owned files. Do not add -L: a helper symlink must never inherit the
# ownership and mode of the privileged file it points at.
_sddm_file_state() {
    stat -c '%U:%G %a' -- "$1" 2>/dev/null
}

# Resolve directories before checking ownership: a root-owned symlink into a
# user-owned directory is still a user-controlled destination for root writes.
_sddm_resolved_owner() {
    local resolved

    resolved=$(readlink -f -- "$1" 2>/dev/null) || return 0
    stat -c '%U' -- "$resolved" 2>/dev/null
}

# GNU stat does not dereference symlinks unless -L is supplied. Keep that
# property: the cache-file write itself is the event the watcher consumes.
_sddm_path_mtime() {
    stat -c '%Y' -- "$1" 2>/dev/null
}

_sddm_newest_awww_entry() {
    local candidate candidate_mtime newest="" newest_mtime=""

    for candidate in "$DOCTOR_SDDM_AWWW_CACHE"/*/*; do
        [ -f "$candidate" ] || continue
        candidate_mtime=$(_sddm_path_mtime "$candidate")
        [ -n "$candidate_mtime" ] || continue
        if [ -z "$newest_mtime" ] || [ "$candidate_mtime" -gt "$newest_mtime" ]; then
            newest="$candidate"
            newest_mtime="$candidate_mtime"
        fi
    done

    [ -n "$newest" ] && printf '%s\n' "$newest"
}

_sddm_has_passwordless_grant() {
    local listing="$1" helper="$2" username="$3"

    printf '%s\n' "$listing" | awk -v command="$helper $username" '
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

# The privileged helper must remain self-contained after it is copied outside
# the user's home, so its fallback cannot live in a sourced shared file. Parse
# the assignment at the point where the source applies it instead.
_sddm_default_theme() {
    # The dollar expression is the literal syntax being parsed, not shell code.
    # shellcheck disable=SC2016
    sed -n 's/^\[\[ -z "\$current_theme" \]\] && current_theme="\([^"]*\)"$/\1/p' "$1"
}

_sddm_current_theme() {
    grep -A2 "\[Theme\]" "$DOCTOR_SDDM_CONF" 2>/dev/null | \
        grep "^Current=" | cut -d'=' -f2 | tr -d ' '
}

check_sddm() {
    # Silent means silent: not even a group heading belongs on a non-SDDM host.
    _sddm_is_display_manager || return 0

    group "SDDM"

    local before_errors="$DOCTOR_ERRORS"
    local before_warnings="$DOCTOR_WARNINGS"
    local before_notices="$DOCTOR_NOTICES"
    local setup_script="$DOCTOR_ROOT/sddm/setup-sudo.sh"
    local root_source="$DOCTOR_ROOT/sddm/update_sddm_root.sh"
    local update_script="$DOCTOR_ROOT/sddm/update_sddm.sh"
    local watcher="$DOCTOR_ROOT/sddm/watch_wallpaper.sh"
    local sudoers_file installed_helper default_theme current_theme
    local theme_dir backgrounds_dir background sudo_listing grant_user helper_state
    local theme_owner backgrounds_owner trigger trigger_mtime background_mtime

    if [ ! -f "$setup_script" ]; then
        err "cannot derive SDDM privileged paths because sddm/setup-sudo.sh is missing" \
            "restore $(doctor_q "$setup_script") from the dotfiles repository"
        return 0
    fi

    sudoers_file=$(doctor_assignment "$setup_script" SUDOERS_FILE)
    installed_helper=$(doctor_assignment "$setup_script" INSTALLED_HELPER)
    if [ -z "$sudoers_file" ] || [ -z "$installed_helper" ]; then
        err "cannot derive SDDM privileged paths from sddm/setup-sudo.sh" \
            "restore the plain path assignments in $(doctor_q "$setup_script")"
        return 0
    fi

    default_theme=$(_sddm_default_theme "$root_source")
    if [ -z "$default_theme" ]; then
        err "cannot derive the default SDDM theme from sddm/update_sddm_root.sh" \
            "restore the default-theme assignment in $(doctor_q "$root_source")"
        return 0
    fi

    sudo_listing=$(_sddm_sudo_listing || true)
    grant_user=$(_sddm_username)
    if [ -n "$grant_user" ] &&
       _sddm_has_passwordless_grant "$sudo_listing" "$installed_helper" "$grant_user"; then
        :
    else
        err "$installed_helper is not in the effective passwordless sudo permissions (expected via $sudoers_file)" \
            "run $(doctor_q "$setup_script")"
    fi

    if [ -L "$installed_helper" ]; then
        err "installed SDDM wallpaper helper must not be a symlink: $installed_helper" \
            "run $(doctor_q "$setup_script")"
    elif [ ! -f "$installed_helper" ]; then
        err "installed SDDM wallpaper helper is missing: $installed_helper" \
            "run $(doctor_q "$setup_script")"
    else
        helper_state=$(_sddm_file_state "$installed_helper")
        if [ "$helper_state" != "root:root 755" ]; then
            err "installed SDDM wallpaper helper has unsafe ownership or mode ($helper_state; expected root:root 755)" \
                "run $(doctor_q "$setup_script")"
        fi
        if ! cmp -s "$root_source" "$installed_helper"; then
            warn "installed SDDM wallpaper helper differs from the tracked source" \
                 "re-run $(doctor_q "$setup_script")"
        fi
    fi

    if ! _sddm_have_ffmpeg; then
        err "ffmpeg is not installed — the SDDM wallpaper updater cannot convert images" \
            "install ffmpeg with sudo pacman -S ffmpeg"
    fi

    if ! _sddm_watcher_running; then
        warn "SDDM wallpaper watcher is not running — wallpaper switches will not reach the greeter" \
             "start $(doctor_q "$watcher") or log into Hyprland again"
    fi

    current_theme=$(_sddm_current_theme)
    [ -n "$current_theme" ] || current_theme="$default_theme"
    theme_dir="$DOCTOR_SDDM_THEMES/$current_theme"
    backgrounds_dir="$theme_dir/Backgrounds"
    background="$backgrounds_dir/wallpaper.jpg"

    if [ -d "$theme_dir" ]; then
        theme_owner=$(_sddm_resolved_owner "$theme_dir")
        if [ -z "$theme_owner" ]; then
            err "cannot determine ownership of the resolved SDDM theme directory: $theme_dir" \
                "restore a root-owned SDDM theme directory before enabling wallpaper sync"
        elif [ "$theme_owner" != "root" ]; then
            err "resolved SDDM theme directory is owned by $theme_owner, not root — the privileged helper writes into a user-controlled directory: $theme_dir" \
                "restore root ownership of the theme directory before enabling wallpaper sync"
        elif [ -d "$backgrounds_dir" ]; then
            backgrounds_owner=$(_sddm_resolved_owner "$backgrounds_dir")
            if [ -z "$backgrounds_owner" ]; then
                err "cannot determine ownership of the resolved SDDM Backgrounds directory: $backgrounds_dir" \
                    "restore a root-owned Backgrounds directory before enabling wallpaper sync"
            elif [ "$backgrounds_owner" != "root" ]; then
                err "resolved SDDM Backgrounds directory is owned by $backgrounds_owner, not root — the privileged helper writes into a user-controlled directory: $backgrounds_dir" \
                    "restore root ownership of the Backgrounds directory before enabling wallpaper sync"
            fi
        fi
    fi

    if [ ! -e "$background" ]; then
        warn "SDDM greeter background is missing: $background" \
             "after repairing passwordless sudo, run $(doctor_q "$update_script")"
    fi

    trigger=$(_sddm_newest_awww_entry)
    if [ -n "$trigger" ] && [ -e "$background" ]; then
        trigger_mtime=$(_sddm_path_mtime "$trigger")
        background_mtime=$(_sddm_path_mtime "$background")
        if [ -n "$trigger_mtime" ] && [ -n "$background_mtime" ] &&
           [ "$trigger_mtime" -gt "$background_mtime" ]; then
            warn "SDDM greeter background is older than the newest awww cache update — the last sync did not complete" \
                 "after repairing passwordless sudo, run $(doctor_q "$update_script")"
        fi
    fi

    if [ "$DOCTOR_ERRORS" -eq "$before_errors" ] &&
       [ "$DOCTOR_WARNINGS" -eq "$before_warnings" ] &&
       [ "$DOCTOR_NOTICES" -eq "$before_notices" ]; then
        ok "SDDM wallpaper sync is healthy"
    fi
}
