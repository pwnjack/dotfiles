#!/bin/bash
#
# SSH agent wiring (scripts/ssh/setup.sh): passphrase once per login.
#
# Nothing is restated here. The socket name comes from the SSH_AUTH_SOCK line
# of hypr/config/setup/envvars.lua, and the unit name and Include line from
# scripts/ssh/setup.sh, which owns them.
#
# Every finding is a WARN: without the agent ssh still works and just asks for
# the passphrase on every use. A shell started before the setup, which lacks
# SSH_AUTH_SOCK until the next login, is only a note; so is a shell that uses
# another agent (forwarded, gpg-agent, gcr).
#
# Two details mirror setup.sh: the first line of ~/.ssh/config is compared
# without trailing whitespace (ssh ignores it, a CR included), and the tracked
# ssh/config fragment is warned about when group or world writable, because ssh
# refuses such an Include target ("Bad owner or permissions") and then every
# ssh call fails.
#
# Trees without envvars.lua, or whose file sets no SSH_AUTH_SOCK, get no output: the feature does not apply there.

_ssh_unit_enabled() {
    systemctl --user is-enabled --quiet "$1" 2>/dev/null
}

_ssh_socket_live() {
    [ -S "$1" ]
}

_ssh_home() {
    printf '%s' "$HOME"
}

# Whether a user bus is reachable from this shell.
_ssh_user_bus() {
    systemctl --user show-environment >/dev/null 2>&1
}

# Whether the user manager can see the unit file at all.
_ssh_unit_present() {
    systemctl --user cat "$1" >/dev/null 2>&1
}

_ssh_runtime_dir() {
    printf '%s' "${XDG_RUNTIME_DIR:-}"
}

_ssh_session_sock() {
    printf '%s' "${SSH_AUTH_SOCK:-}"
}

# _ssh_file_mode <file> — the octal permission bits.
_ssh_file_mode() {
    stat -c %a -- "$1" 2>/dev/null
}

# _ssh_socket_name <envvars.lua> — the "/name" after `runtime ..` in the
# hl.env("SSH_AUTH_SOCK", ...) line. scripts/ssh/setup.sh uses the same sed.
_ssh_socket_name() {
    sed -n '/^[[:space:]]*--/b;/hl\.env("SSH_AUTH_SOCK"/{s/.*hl\.env("SSH_AUTH_SOCK", *runtime *\.\. *"\([^"]*\)" *\(, *true *\)\{0,1\}).*/\1/p;q;}' "$1" 2>/dev/null
}

check_ssh() {
    local envlua="$DOCTOR_ROOT/hypr/config/setup/envvars.lua"
    local setup="$DOCTOR_ROOT/scripts/ssh/setup.sh"
    local fragment="$DOCTOR_ROOT/ssh/config"
    local sock name unit include config first="" fix mode target found=0 nosock=0 session

    [ -f "$envlua" ] || return 0
    name=$(_ssh_socket_name "$envlua")
    [ -n "$name" ] || return 0
    group "SSH agent"

    unit=$(doctor_assignment "$setup" SSH_AGENT_UNIT)
    include=$(doctor_assignment "$setup" INCLUDE_LINE)
    if [ -z "$unit" ] || [ -z "$include" ]; then
        warn "cannot derive the agent unit and Include line from scripts/ssh/setup.sh" \
            "git -C $(doctor_q "$DOCTOR_ROOT") diff -- scripts/ssh/setup.sh"
        return 0
    fi
    sock="$(_ssh_runtime_dir)$name"
    # su, sudo -u and cron carry no runtime dir: the socket path is unknowable.
    if [ -z "$(_ssh_runtime_dir)" ] || ! _ssh_user_bus; then nosock=1; fi
    fix="bash $(doctor_q "$setup")"

    if [ "$nosock" -eq 1 ]; then
        :  # no runtime dir means no user bus: neither unit nor socket can be judged
    elif ! _ssh_unit_present "$unit"; then
        warn "$unit is not installed (it ships with openssh)"
        found=1
    elif ! _ssh_unit_enabled "$unit"; then
        warn "$unit is not enabled — ssh asks for the passphrase on every use" "$fix"
        found=1
    elif ! _ssh_socket_live "$sock"; then
        warn "nothing is listening at $sock" "systemctl --user restart $(doctor_q "$unit")"
        found=1
    fi

    config="$(_ssh_home)/.ssh/config"
    if [ -f "$config" ] && [ ! -r "$config" ]; then
        warn "$config is not readable" "chmod u+r $(doctor_q "$config")"
        found=1
    else
        if [ -f "$config" ]; then IFS= read -r first 2>/dev/null < "$config" || true; fi
        first=${first%"${first##*[![:space:]]}"}
        if [ "$first" = "$include" ]; then
            :
        elif [ -L "$config" ]; then
            # setup.sh leaves a symlinked config alone, so its hint cannot clear this.
            target=$(readlink -f -- "$config")
            [ -n "$target" ] || target=$(readlink -- "$config")
            warn "$config is a symlink whose target does not start with: $include" \
                "add that line at the top of $(doctor_q "$target")"
            found=1
        elif [ ! -e "$config" ]; then
            warn "$config does not exist" "$fix"
            found=1
        else
            warn "$config does not start with: $include" "$fix"
            found=1
        fi
    fi

    if [ -f "$fragment" ]; then
        mode=$(_ssh_file_mode "$fragment")
        if [[ $mode =~ ^[0-7]+$ ]] && [ $((8#$mode & 8#022)) -ne 0 ]; then
            warn "$fragment is group/world writable — ssh refuses to include it" \
                "chmod go-w $(doctor_q "$fragment")"
            found=1
        fi
    fi

    if [ "$nosock" -eq 1 ]; then
        note "no user session bus in this shell — cannot check the agent unit or socket"
        found=1
    elif [ "$found" -eq 0 ]; then
        session=$(_ssh_session_sock)
        if [ -z "$session" ]; then
            note "this shell has no SSH_AUTH_SOCK yet — log out and back in"
            found=1
        elif [ "$session" != "$sock" ]; then
            note "this shell uses another agent at $session (forwarded, gpg-agent or gcr?)"
            found=1
        fi
    fi

    [ "$found" -eq 0 ] && ok "the SSH agent is wired: passphrase once per login"
    return 0
}
