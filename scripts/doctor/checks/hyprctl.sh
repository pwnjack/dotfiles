#!/bin/bash
#
# Runtime hyprctl compatibility for Hyprland's Lua config provider.
#
# Hyprland's Lua provider does not accept `hyprctl keyword`, and dispatchers
# must be passed as Lua expressions rather than the legacy positional form.
# Waybar's hyprland/workspaces module also embeds a positional `workspace`
# dispatcher in its button implementation, even though no such command appears
# in config.jsonc. Scan every tracked text file and that placed module so panel
# code, Waybar handlers and scripts are covered. Documentation and the doctor's
# own fixtures are excluded because both intentionally discuss old examples.
#
# This is a WARN: one control or action is broken when invoked, but Hyprland
# and the rest of the session continue to run.

# _hctl_uses_lua_provider
# The tracked entrypoint is the source of truth; do not infer this from the
# currently running compositor, which may be older than the checked-out tree.
_hctl_uses_lua_provider() {
    git -C "$DOCTOR_ROOT" ls-files --error-unmatch -- hypr/hyprland.lua >/dev/null 2>&1
}

# _hctl_uses_native_waybar_workspaces
# True only when hyprland/workspaces is placed in a bar array or a group, read
# by waybar.sh's _way_placed (sourced before this module). A configured but
# unplaced block cannot break clicks, and a commented entry is not configuration.
_hctl_uses_native_waybar_workspaces() {
    local config="$DOCTOR_ROOT/waybar/config.jsonc"
    [ -f "$config" ] || return 1
    _way_placed "$config" | grep -qx 'hyprland/workspaces'
}

# _hctl_check_file <root-relative-file>
_hctl_check_file() {
    local file="$1" full="$DOCTOR_ROOT/$1" quoted_full line trimmed line_no=0
    local shell_keyword_re='hyprctl[[:space:]]+keyword([[:space:]]|$)'
    local shell_dispatch_re='hyprctl[[:space:]]+dispatch[[:space:]]+[A-Za-z_]'
    local array_keyword_re="['\"]hyprctl['\"][[:space:]]*,[[:space:]]*['\"]keyword['\"]"
    local array_dispatch_re="['\"]hyprctl['\"][[:space:]]*,[[:space:]]*['\"]dispatch['\"][[:space:]]*,[[:space:]]*['\"][A-Za-z_][A-Za-z0-9_-]*['\"]"

    [ -f "$full" ] || return 0
    [ -L "$full" ] && return 0
    LC_ALL=C grep -Iq hyprctl "$full" 2>/dev/null || return 0
    quoted_full="$(doctor_q "$full")"

    while IFS= read -r line || [ -n "$line" ]; do
        line_no=$((line_no + 1))
        trimmed="${line#"${line%%[![:space:]]*}"}"
        case "$trimmed" in
            \#*|'--'*|'//'*) continue ;;
        esac

        if [[ "$line" =~ $shell_keyword_re ]] \
            || [[ "$line" =~ $shell_dispatch_re ]] \
            || [[ "$line" =~ $array_keyword_re ]] \
            || [[ "$line" =~ $array_dispatch_re ]]; then
            warn "$file:$line_no uses hyprctl syntax removed by the Lua config provider" \
                "replace the call in $quoted_full with hyprctl eval or a Lua dispatcher expression"
        fi
    done < "$full"
}

check_hyprctl() {
    group "Hyprctl Lua compatibility"

    local before
    before=$(doctor_findings)
    local file

    if ! _hctl_uses_lua_provider; then
        ok "the tracked configuration does not use Hyprland's Lua provider"
        return 0
    fi

    if _hctl_uses_native_waybar_workspaces; then
        local waybar_config="$DOCTOR_ROOT/waybar/config.jsonc"
        warn "waybar places hyprland/workspaces, whose clicks use a dispatcher removed by the Lua config provider" \
            "replace it with ext/workspaces in $(doctor_q "$waybar_config")"
    fi

    while IFS= read -r -d '' file; do
        case "$file" in
            docs/*|scripts/doctor/*|*.md) continue ;;
        esac
        _hctl_check_file "$file"
    done < <(git -C "$DOCTOR_ROOT" ls-files -z 2>/dev/null)

    ok_if_clean "$before" "tracked runtime calls use the Lua-compatible hyprctl API"
}
