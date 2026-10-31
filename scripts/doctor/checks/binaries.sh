#!/bin/bash
#
# Binary availability for everything the keybinds and autostart invoke.
#
# Targets are extracted from keybinds.lua and autostart.lua, so binding a new
# command extends coverage automatically. Application-table references are
# resolved from options/ and hypr/config/apptype.lua.
#
# It also checks that the screen recorder's KMS helper holds cap_sys_admin.
#
# Everything here is WARN, never ERROR. A keybind pointing at an absent
# binary means one shortcut silently does nothing; the session still starts
# and every other binding still works.
#
# Scope decisions:
#
#   * Scripts under scripts/ are deliberately NOT scanned for the commands
#     they invoke. Reliably extracting invocations from bash defeats naive
#     parsing (variables, heredocs, conditionals, functions), and this repo's
#     scripts already guard with `command -v`. Their paths are still
#     validated by the reference check.
#
#   * Command targets that are paths (/…, ~/…, $HOME/…) are skipped here.
#     references.sh owns "does this file exist"; duplicating it would report
#     one broken keybind twice under two severities.
#
#   * Pipelines and command lists are split, so every segment's binary is
#     checked. `cliphist list | rofi -dmenu | wl-copy` is one keybind but
#     three binaries, and any of them missing breaks the shortcut.
#
#   * A missing binary is reported once globally, not once per binding or
#     per file. Installing it fixes every site at once, so repeating the
#     finding would pad the report without adding an action.
#
# Accepted risks:
#
#   * A token containing `=` is treated as an environment assignment and
#     skipped, so `FOO=bar somecmd` checks nothing. No such binding exists
#     in this repo, and the alternative (guessing which token is the
#     command) is worse than a known blind spot.
#
#   * Command substitutions inside arguments are not evaluated, so a binary
#     invoked only from inside `$( … )` is not checked.
#

# Sourced here rather than from doctor.sh because the test suite sources this
# module directly, without the entry point.
# shellcheck source=../../lib/hypr-vars.sh
source "${BASH_SOURCE[0]%/*}/../../lib/hypr-vars.sh"

# Names already reported this run, space-delimited and space-padded.
_BIN_SEEN=""

# _bin_resolve_var <name> -> value, or empty when undefined.
# The rules live in scripts/lib/hypr-vars.sh, shared with the keybinds
# cheatsheet, which resolves the same variables for display.
_bin_resolve_var() {
    hypr_resolve_var "$1" "$DOCTOR_ROOT"
}

# _bin_check_token <token> <origin-file>
_bin_check_token() {
    local token="$1" origin="$2" bin

    [ -n "$token" ] || return 0

    # Repo paths belong to the reference check. Both `~` and `$HOME` are
    # quoted: an unquoted ~/* in a case pattern is tilde-expanded to the
    # running user's home, so it would never match the literal "~/" in a
    # config. Absolute paths (a package's /usr/lib helper) are checked below.
    case "$token" in
        '~'/*|'$HOME'/*) return 0 ;;
    esac

    # Environment assignments are not commands.
    case "$token" in
        *=*) return 0 ;;
    esac

    if [ "${token:0:1}" = '$' ]; then
        bin="$(_bin_resolve_var "${token#\$}")"
        if [ -z "$bin" ]; then
            warn "$origin invokes $token, which is not defined anywhere" \
                 "define it in hypr/config/apptype.lua, or in options/$(doctor_q "${token#\$}")"
            return 0
        fi
    else
        bin="$token"
    fi

    # Report each missing binary once, however many places bind it.
    case "$_BIN_SEEN" in
        *" $bin "*) return 0 ;;
    esac
    _BIN_SEEN="$_BIN_SEEN $bin "

    command -v "$bin" >/dev/null 2>&1 && return 0

    if [[ $bin == /* ]]; then
        warn "$origin invokes '$bin', which is not an executable file" \
             "pacman -F $(doctor_q "$bin") names the package that ships it"
        return 0
    fi

    # A package of the same name being installed changes the diagnosis
    # completely: the config is not missing a package, it is naming something
    # that was never executable from PATH, so the line silently does nothing.
    if _bin_package_installed "$bin"; then
        warn "$origin invokes '$bin', which is installed but ships no executable on PATH — this line silently does nothing" \
             "pacman -Ql $(doctor_q "$bin") | grep -E 'bin/|systemd' to find the real entry point"
    else
        warn "$origin invokes '$bin', which is not installed" \
             "pacman -S $(doctor_q "$bin")   (or drop it from $(doctor_q "$origin"))"
    fi
}

# _bin_package_installed <name> -> 0 when a package of that name is installed.
# Its own function so the tests can stub it: the real answer is specific to
# whichever machine happens to be running the suite.
_bin_package_installed() {
    command -v pacman >/dev/null 2>&1 || return 1
    pacman -Q "$1" >/dev/null 2>&1
}

# _bin_check_command <raw-command-string> <origin-file>
# Splits pipelines and command lists, then checks each segment's first token.
_bin_check_command() {
    local raw="$1" origin="$2" segment first rest

    raw="${raw%&}"

    while read -r segment; do
        # Leading whitespace would otherwise become the first field.
        read -r first rest <<< "$segment"
        _bin_check_token "$first" "$origin"
        # respawn.sh is checked as a path; the binary it runs is checked here.
        case "$first" in
            */scripts/hyprland/respawn.sh)
                read -r first _ <<< "$rest"
                _bin_check_token "$first" "$origin" ;;
        esac
        _bin_check_systemd_unit "$segment" "$origin"
    done < <(printf '%s\n' "$raw" | sed 's/&&/\n/g; s/||/\n/g; s/[|;]/\n/g')
}

# _bin_unit_exists <unit> -> 0 when systemd knows that user unit.
# Its own function so tests can stub it; the real answer is host-specific.
_bin_unit_exists() {
    command -v systemctl >/dev/null 2>&1 || return 0
    systemctl --user cat "$1" >/dev/null 2>&1
}

# _bin_check_systemd_unit <command-segment> <origin-file>
#
# `systemctl --user start foo.service` passes the binary check trivially —
# systemctl is always installed — so without this the unit name is unchecked
# and a typo fails silently on every login. That is exactly the failure this
# module exists to catch: it is how `exec-once = $polkitAgent` went unnoticed,
# and routing that fix through systemctl would otherwise have blinded the
# check that found it.
_bin_check_systemd_unit() {
    local segment="$1" origin="$2" unit=""

    case "$segment" in
        systemctl*' --user '*) ;;
        *) return 0 ;;
    esac

    # Last whitespace-delimited field, which is the unit for the start/restart/
    # enable forms this repo uses. Anything else is left alone.
    case "$segment" in
        *' start '*|*' restart '*|*' enable '*) unit="${segment##* }" ;;
        *) return 0 ;;
    esac

    [ -n "$unit" ] || return 0
    case "$unit" in
        -*) return 0 ;;   # a flag, not a unit
    esac

    # The Lua scanner represents an apps.polkitAgent concatenation as
    # `$polkitAgent`, so resolve it through the same application-table helper
    # as the binary check. Skipping `$…` tokens here would silently exempt
    # precisely the line this check was added for.
    if [ "${unit:0:1}" = '$' ]; then
        unit="$(_bin_resolve_var "${unit#\$}")"
        [ -n "$unit" ] || return 0   # undefined: already reported as a token
    fi

    if ! _bin_unit_exists "$unit"; then
        warn "$origin starts the systemd user unit '$unit', which systemd does not know" \
             "systemctl --user list-unit-files | grep $(doctor_q "${unit%%.*}")"
    fi
}

# _bin_scan_lua <file-relative-to-root>
# Extracts the command expression from every hl.exec_cmd()/hl.dsp.exec_cmd()
# call. The config keeps each call on one line; these substitutions cover Lua
# quoted strings, long-bracket strings, and the application table references
# used by this repo.
_bin_scan_lua() {
    local conf="$1" line
    [ -f "$DOCTOR_ROOT/$conf" ] || return 0

    while read -r line; do
        _bin_check_command "$line" "$conf"
    done < <(sed -nE \
        -e 's/.*exec_cmd\(\[\[(.*)\]\]\).*/\1/p' \
        -e 's/.*exec_cmd\("([^"]*)"\).*/\1/p' \
        -e 's/.*exec_cmd\(apps\.terminal \.\. " -e " \.\. apps\.editor\).*/$terminal -e $editor/p' \
        -e 's/.*exec_cmd\(apps\.([A-Za-z_][A-Za-z0-9_]*)\).*/$\1/p' \
        -e 's/.*exec_cmd\("([^"]*)" \.\. apps\.([A-Za-z_][A-Za-z0-9_]*)\).*/\1$\2/p' \
        "$DOCTOR_ROOT/$conf")
}

# _bin_kms_path <name> -> the helper's absolute path, or empty. Its own
# function so the tests can stub it.
_bin_kms_path() {
    command -v "$1" 2>/dev/null
}

# _bin_capability <path> -> getcap's line for it; 1 when getcap is absent.
# Its own function so the tests can stub it.
_bin_capability() {
    command -v getcap >/dev/null 2>&1 || return 1
    getcap "$1" 2>/dev/null
}

# _bin_check_capture
# Screen recording (scripts/capture/record.sh) captures through KMS, which
# needs the recorder's helper to hold cap_sys_admin; the package's install
# script sets it with setcap. A copy, or an install from a cache that lost the
# xattr, drops it, and every recording then fails at start. The helper's
# name is read from record.sh, so this check names no binary itself. A
# recorder that is not installed is record.sh's to report (it toasts).
_bin_check_capture() {
    local name path caps
    name=$(sed -n 's/^readonly KMS_SERVER=\([A-Za-z0-9_.-]*\)$/\1/p' \
        "$DOCTOR_ROOT/scripts/capture/record.sh" 2>/dev/null)
    [ -n "$name" ] || return 0
    path=$(_bin_kms_path "$name")
    [ -n "$path" ] || return 0
    caps=$(_bin_capability "$path") || return 0
    case "$caps" in
        *cap_sys_admin*) return 0 ;;
    esac
    warn "$path lacks cap_sys_admin, so screen recording cannot capture the screen" \
         "sudo setcap cap_sys_admin+ep $(doctor_q "$path")"
}

check_binaries() {
    group "Binaries"

    local before_e="$DOCTOR_ERRORS" before_w="$DOCTOR_WARNINGS" before_n="$DOCTOR_NOTICES"
    _BIN_SEEN=""

    _bin_scan_lua "hypr/config/software/keybinds.lua"
    _bin_scan_lua "hypr/config/setup/autostart.lua"
    _bin_check_capture

    if [ "$DOCTOR_ERRORS" = "$before_e" ] \
        && [ "$DOCTOR_WARNINGS" = "$before_w" ] \
        && [ "$DOCTOR_NOTICES" = "$before_n" ]; then
        ok "every referenced binary is installed and the capture helper has its capability"
    fi
}
