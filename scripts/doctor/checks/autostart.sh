#!/bin/bash
#
# Per-user XDG autostart entries: the settings panel's Startup page writes
# them, and systemd's generator silently skips an entry whose program is not
# installed (arch-update-tray.desktop did exactly that). Everything is derived
# from the files themselves; nothing is listed here.
#
# The rules follow systemd 262's xdg-autostart-generator as far as this check
# needs (quickshell/settings-panel/autostart.mjs carries the full set): only
# non-dot *.desktop files count; Hidden is a case-insensitive boolean and the
# last definition wins; an entry whose Type is not Application is skipped; the
# entry needs BOTH its TryExec (looked up verbatim, never split) and the first
# word of Exec to resolve. X-GNOME-Autostart-enabled is ignored by systemd, so
# it is ignored here.
#
# These files are untracked (.gitignore: autostart/**), so this check reads
# live state rather than git. Severity is WARN: a missing tray applet never
# breaks the session.

DOCTOR_AUTOSTART_DIR="${DOCTOR_AUTOSTART_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/autostart}"
DOCTOR_AUTOSTART_SYSTEM="${DOCTOR_AUTOSTART_SYSTEM:-/etc/xdg/autostart}"

# _as_have_cmd <binary> — host probe, its own function so tests can stub it.
# type -P finds files only, so a shell builtin never stands in for a program.
_as_have_cmd() { type -P -- "$1" >/dev/null 2>&1; }

# _as_hidden <file> — Hidden, as systemd reads it: last definition, boolean.
_as_hidden() {
    case "$(doctor_ini "$1" 'Desktop Entry' Hidden last)" in
        [1yYtT]|[yY][eE][sS]|[tT][rR][uU][eE]|[oO][nN]) return 0 ;;
    esac
    return 1
}

# _as_exec_word <file> -> the first word of Exec (either quote style honoured).
_as_exec_word() {
    local value
    value="$(doctor_ini "$1" 'Desktop Entry' Exec)"
    case "$value" in
        \"*) value="${value#\"}"; printf '%s\n' "${value%%\"*}" ;;
        \'*) value="${value#\'}"; printf '%s\n' "${value%%\'*}" ;;
        *) printf '%s\n' "${value%%[[:space:]]*}" ;;
    esac
}

# _as_minimal <file> — exactly the four-line override the panel writes.
_as_minimal() {
    local lines
    lines="$(grep -v -e '^[[:space:]]*$' -e '^[[:space:]]*#' "$1")"
    [ "$(printf '%s\n' "$lines" | wc -l)" -eq 4 ] &&
        printf '%s\n' "$lines" | grep -qx '\[Desktop Entry\]' &&
        printf '%s\n' "$lines" | grep -qx 'Type=Application' &&
        printf '%s\n' "$lines" | grep -qx 'Hidden=true' &&
        printf '%s\n' "$lines" | grep -q '^Name='
}

check_autostart() {
    group "Autostart"
    local file name tryexec word missing before
    before=$(doctor_findings)
    if [ -d "$DOCTOR_AUTOSTART_DIR" ]; then
        while IFS= read -r -d '' file; do
            name="${file##*/}"
            # systemd follows a symlinked entry, and silently ignores a dangling one.
            if [ -L "$file" ] && [ ! -e "$file" ]; then
                warn "$name is a link to a missing file, so systemd ignores it" "rm $(doctor_q "$file")"
                continue
            fi
            if _as_hidden "$file"; then
                if _as_minimal "$file" && [ ! -e "$DOCTOR_AUTOSTART_SYSTEM/$name" ]; then
                    note "$name hides a system autostart entry that no longer exists" "rm $(doctor_q "$file")"
                fi
                continue
            fi
            [ "$(doctor_ini "$file" 'Desktop Entry' Type)" = "Application" ] || continue
            word="$(_as_exec_word "$file")"
            [ -n "$word" ] || continue
            tryexec="$(doctor_ini "$file" 'Desktop Entry' TryExec)"
            missing=""
            if [ -n "$tryexec" ] && ! _as_have_cmd "$tryexec"; then missing="$tryexec"; fi
            if ! _as_have_cmd "$word"; then missing="${missing:+$missing and }$word"; fi
            if [ -n "$missing" ]; then
                warn "$name starts $missing, which is not installed, so it never runs" "install the program, or rm $(doctor_q "$file")"
            fi
        done < <(find "$DOCTOR_AUTOSTART_DIR" -maxdepth 1 \( -type f -o -type l \) -name '*.desktop' ! -name '.*' -print0 | sort -z)
    fi
    ok_if_clean "$before" "Every per-user autostart entry resolves"
}
