#!/bin/bash
#
# Autostart daemons, respawn.sh units gone failed, D-Bus role ownership, and
# install.sh package drift.
#
# Four independent probes share one module because they are the four ways
# this repo's runtime state can silently diverge from its config without any
# file going missing (which the other checks already cover):
#
#   1. Daemon list — derived from bare-binary `hl.exec_cmd()` calls in
#      autostart.lua, the same source binaries.sh already scans. A line is a
#      daemon candidate only when its first token has no `/`, `~/` or `$`
#      prefix: those forms name a one-shot script or an unresolved variable,
#      neither of which is "a process that should still be alive". This is
#      deliberately the same split binaries.sh uses for the identical reason.
#
#      An unquoted `~/*` case pattern is tilde-expanded to the running user's
#      home before matching, so it can never match a literal "~/" in a config
#      file — a real bug caught in the binaries.sh task and fixed the same way
#      here: quote the tilde.
#
#   1b. Wrapped daemons — the respawn.sh lines of the same list. Their package
#      may ship D-Bus activation naming a systemd user unit, which starts a
#      second copy when a client calls the bus name before ours owns it. The
#      copy exits at once and the unit ends `failed`; a drop-in under
#      systemd/user/<unit>.d/ keeps it from starting, and a unit that is
#      failed anyway is WARN. Unit names equal binary names here; an unknown
#      unit is not failed, so a daemon without one needs no special case.
#
#   2. D-Bus role ownership — DOCTOR_DBUS_ROLE names one well-known bus name
#      that only a single process can hold. Only the notification daemon is in
#      scope; scaling to more would need the variable to become a newline list
#      and the lookup below to loop over it, which is not worth building for a
#      set of one.
#
#      Which packages compete for that name is DERIVED, not listed. Every
#      program able to own a well-known bus name ships an activation file
#      under /usr/share/dbus-1/services declaring `Name=<bus-name>`, and
#      `pacman -Qoq` maps that file back to its package. Installing a third
#      notification daemon therefore extends coverage on its own.
#
#      pacman's own Provides field is deliberately NOT used. Verified on the
#      live system: `pacman -Qi mako` and `pacman -Qi swaync` both print
#      "Provides : None", so a Provides lookup finds nothing and the orphan
#      finding — the reason this section exists — would never fire.
#
#   3. Package drift — PACKAGES and AUR_PACKAGES arrays parsed out of
#      install.sh. Verified against the live file (lines 89-121): both arrays
#      close on a bare `)` at column 0 with no continuation, which is what the
#      awk state machine below assumes. If a future edit indents the closing
#      paren or puts a second array entry on that line, the parser silently
#      stops seeing members past that point — a silent under-report, not a
#      crash, and worth knowing if this check ever looks confidently wrong.
#
# Severity: a daemon not running is WARN (one feature — the thing it does —
# stops working, but the session is fine). Everything else here is INFO: who
# owns a D-Bus name, an orphaned config directory, a package drifted out of
# install.sh — all tidiness, nothing broken. Nothing in this module is ever
# ERROR: there is no daemon whose absence breaks the session itself (that is
# what binaries.sh's WARN-only stance already argues for the same targets).
#
# Accepted risks:
#
#   * The daemon-running check does not verify a matching package is
#     installed first. "Installed but not running" in the task brief is read
#     as "autostart declares it, so it is expected to be alive" rather than a
#     literal pacman cross-check — the binary-to-package name mapping is not
#     1:1 (`swayosd-server` ships from package `swayosd`) and reconstructing
#     that mapping is its own project. A daemon
#     that was deliberately uninstalled still gets one WARN instead of silence
#     — a known false positive, cheap to dismiss, cheaper than a wrong map.
#
#   * `pgrep -x` matches on `comm`, which the kernel truncates at 15 bytes.
#     Every name in this repo's autostart.lua is short enough that this never
#     bites (`swayosd-server` is 14 bytes, the longest of them), so no
#     workaround is implemented. `pgrep -f` was tried and rejected: it matches
#     full command lines, so `pgrep -f swaync` can match an unrelated shell
#     invocation that merely mentions "swaync" in its argv, and `-f hypridle`
#     etc. are just as porous. `-x` is the correct tool here, not a shortcut.
#
#   * `pacman`, `busctl` and `pgrep` availability are each checked once in
#      check_services before the loop that depends on them, not inside every
#      iteration — so an unavailable tool skips the whole probe silently
#      instead of one warning-shaped finding per item.
#

# The single-owner bus name being audited. See the header note on why this
# stays one value instead of a newline list.
DOCTOR_DBUS_ROLE="org.freedesktop.Notifications"

# _svc_autostart_daemons -> bare-binary autostart targets, one per line,
# deduplicated. Reads with process substitution, per the lib.sh contract:
# piping sed's output into the read loop would run the loop in a subshell and
# lose whatever it printed to the parent's stdout redirection along with it
# (nothing here touches a severity counter, but the shape is kept identical to
# every other check so the contract stays mechanically checkable by grep, not
# by memory).
_svc_autostart_daemons() {
    local conf="$DOCTOR_ROOT/hypr/config/setup/autostart.lua" line first rest
    local commands
    [ -f "$conf" ] || return 0
    commands="$(sed -nE 's/^[[:space:]]*hl\.exec_cmd\("([^"]*)"\).*/\1/p' "$conf")"

    while read -r line; do
        line="${line%&}"
        read -r first rest <<< "$line"
        # respawn.sh only supervises: the daemon is the command it wraps.
        case "$first" in
            */scripts/hyprland/respawn.sh) read -r first _ <<< "$rest" ;;
        esac
        [ -n "$first" ] || continue
        # Quoted: an unquoted ~/* here is tilde-expanded to $HOME before the
        # case match runs, so it would never match a literal "~/" in a file.
        case "$first" in
            /*|'~'/*|'$'*) continue ;;
        esac
        printf '%s\n' "$first"
    done < <(printf '%s\n' "$commands") | sort -u
}

# _svc_wrapped_daemons -> the autostart targets started through respawn.sh,
# one per line, deduplicated, by base name (as respawn.sh names them), so the
# polkit agent's path gives the unit name a lookup would use.
_svc_wrapped_daemons() {
    local conf="$DOCTOR_ROOT/hypr/config/setup/autostart.lua"
    [ -f "$conf" ] || return 0
    sed -nE 's/^[[:space:]]*hl\.exec_cmd\("[^"]*\/scripts\/hyprland\/respawn\.sh +([^ "]*\/)?([^ "\/]+).*"\).*/\2/p' "$conf" | sort -u
}

# _svc_unit_failed <unit> -> 0 when that systemd user unit is in the failed
# state. Non-zero when systemctl is absent or the unit is unknown.
_svc_unit_failed() {
    command -v systemctl >/dev/null 2>&1 || return 1
    systemctl --user is-failed --quiet "$1" 2>/dev/null
}

# _svc_install_packages -> every PACKAGES/AUR_PACKAGES entry in install.sh,
# one per line, deduplicated. See the header note on the `)`-at-column-0
# assumption this relies on.
_svc_install_packages() {
    local installer="$DOCTOR_ROOT/install.sh"
    [ -f "$installer" ] || return 0

    awk '
        /^(PACKAGES|AUR_PACKAGES)=\(/ { inside = 1; next }
        inside && /^\)/               { inside = 0; next }
        inside                        { print }
    ' "$installer" | sed 's/#.*//' | tr -d '"' | tr ' ' '\n' | sed '/^[[:space:]]*$/d' | sort -u
}

# _svc_is_running <name> -> 0 if a process with that exact `comm` is alive.
# Its own function so tests can stub it: the real answer is this machine's
# process table at the moment the suite runs.
_svc_is_running() {
    command -v pgrep >/dev/null 2>&1 || return 1
    pgrep -x "$1" >/dev/null 2>&1
}

# _svc_package_installed <name> -> 0 when a package of that name is installed.
_svc_package_installed() {
    command -v pacman >/dev/null 2>&1 || return 1
    pacman -Q "$1" >/dev/null 2>&1
}

# _svc_bus_owner <bus-name> -> the process name that owns it on the session
# bus, or empty (and non-zero) if nothing does or busctl is unavailable.
_svc_bus_owner() {
    command -v busctl >/dev/null 2>&1 || return 1
    busctl --user list 2>/dev/null | awk -v n="$1" '$1 == n { print $3; found=1 } END { exit !found }'
}

# Where D-Bus publishes its activation files. Overridable for tests.
DOCTOR_DBUS_SERVICES="${DOCTOR_DBUS_SERVICES:-/usr/share/dbus-1/services}"

# _svc_role_providers <bus-name> -> package names implementing that bus name,
# one per line.
#
# Derived, never listed. Every program that can own a well-known D-Bus name
# ships an activation file declaring `Name=<bus-name>`, and pacman maps that
# file back to its owning package. So installing a third notification daemon
# extends coverage on its own.
#
# pacman's Provides field is deliberately NOT used: verified on this machine
# that `pacman -Qi mako` and `pacman -Qi swaync` both print "Provides : None",
# so a Provides lookup would find nothing and the orphan finding — the reason
# this section exists — would never fire.
# _svc_role_service_files <bus-name> -> activation files declaring that name.
# Split out from the package lookup below so the scanning half can be tested
# against a fixture directory without needing pacman to know about it.
_svc_role_service_files() {
    [ -d "$DOCTOR_DBUS_SERVICES" ] || return 0
    grep -lFx "Name=$1" "$DOCTOR_DBUS_SERVICES"/*.service 2>/dev/null
}

_svc_role_providers() {
    local file pkg

    command -v pacman >/dev/null 2>&1 || return 0

    while read -r file; do
        [ -n "$file" ] || continue
        pkg="$(pacman -Qoq "$file" 2>/dev/null)"
        [ -n "$pkg" ] || continue
        printf '%s\n' "$pkg"
    done < <(_svc_role_service_files "$1")
}

# _svc_has_tracked_config <dir> -> 0 if git tracks anything under DOCTOR_ROOT/dir.
# Derived from git rather than `[ -d ]` so an untracked leftover directory
# (build output, a stray cache) is never mistaken for a repo-managed config,
# matching how symlinks.sh and references.sh source their truth from git.
_svc_has_tracked_config() {
    [ -n "$(git -C "$DOCTOR_ROOT" ls-files -- "$1" 2>/dev/null | head -n1)" ]
}

check_services() {
    group "Services"

    local before_e="$DOCTOR_ERRORS" before_w="$DOCTOR_WARNINGS" before_n="$DOCTOR_NOTICES"
    local daemon pkg owner candidate

    # --- 1. autostart daemons actually running -----------------------------
    while read -r daemon; do
        [ -n "$daemon" ] || continue
        _svc_is_running "$daemon" && continue
        warn "'$daemon' is declared in autostart.lua but is not running" \
             "check what happened to it: journalctl --user -b | grep $(doctor_q "$daemon")"
    done < <(_svc_autostart_daemons)

    # --- 1b. respawn.sh daemons whose packaged unit started a second copy ---
    while read -r daemon; do
        [ -n "$daemon" ] || continue
        _svc_unit_failed "$daemon.service" || continue
        warn "'$daemon' runs under respawn.sh but its unit $(doctor_q "$daemon.service") is failed" \
             "systemctl --user status $(doctor_q "$daemon.service"); then systemctl --user reset-failed $(doctor_q "$daemon.service")"
    done < <(_svc_wrapped_daemons)

    # --- 2. install.sh packages actually installed --------------------------
    if command -v pacman >/dev/null 2>&1; then
        while read -r pkg; do
            [ -n "$pkg" ] || continue
            _svc_package_installed "$pkg" && continue
            note "install.sh lists '$pkg' but it is not installed" \
                 "pacman -S $(doctor_q "$pkg")   (or your AUR helper, if it is AUR-only)"
        done < <(_svc_install_packages)
    fi

    # --- 3. D-Bus role ownership + orphaned notification-daemon configs ----
    if command -v busctl >/dev/null 2>&1; then
        local bus_name="$DOCTOR_DBUS_ROLE"
        owner="$(_svc_bus_owner "$bus_name")"
        if [ -n "$owner" ]; then
            note "$bus_name is currently owned by '$owner'"
            while read -r candidate; do
                [ -n "$candidate" ] || continue
                [ "$candidate" = "$owner" ] && continue
                _svc_has_tracked_config "$candidate" || continue
                note "'$candidate' is installed with a tracked config at $(doctor_q "$candidate")/ but does not own $bus_name — its config has no effect while '$owner' holds the name" \
                     "either uninstall $(doctor_q "$candidate"), or stop '$owner' and let $(doctor_q "$candidate") own $bus_name"
            done < <(_svc_role_providers "$bus_name")
        fi
    fi

    if [ "$DOCTOR_ERRORS" = "$before_e" ] \
        && [ "$DOCTOR_WARNINGS" = "$before_w" ] \
        && [ "$DOCTOR_NOTICES" = "$before_n" ]; then
        ok "every autostart daemon is running, no respawn.sh unit has failed, install.sh packages are present, and no D-Bus role is contested"
    fi
}
