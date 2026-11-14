#!/bin/bash
#
# Resolution of application names referenced by the Lua configuration.
#
# Anything that reads a config line afterwards has to resolve the application
# table the same way. Three things do: the doctor's binary and default-app
# checks, which need the command a keybind or an export really runs, and the
# keybinds cheatsheet, which labels `$terminal` with the terminal you use.
# Every answer is parsed from hypr/config/apptype.lua, so a new entry there is
# picked up with no list to update here.
#
# Sourced, never executed. It defines functions and nothing else, so sourcing
# it twice in one shell is harmless.
#

# shellcheck source=scripts/lib/options.sh
. "${BASH_SOURCE[0]%/*}/options.sh"

# _hypr_apptype_line <name> <root> -> apptype.lua's `name = …` line, or 1.
_hypr_apptype_line() {
    local line
    line=$(grep -E "^[[:space:]]*$1[[:space:]]*=" "$2/hypr/config/apptype.lua" 2>/dev/null | head -n 1)
    [ -n "$line" ] && printf '%s' "$line"
}

# hypr_var_option <name> <root> -> the options/ file apptype.lua reads for
# `name` (cursorTheme -> cursortheme), or 1 when `name` is not option-backed.
hypr_var_option() {
    local line
    line=$(_hypr_apptype_line "$1" "$2") || return 1
    [[ $line =~ read_option\(\"([^\"]+)\" ]] || return 1
    printf '%s' "${BASH_REMATCH[1]}"
}

# hypr_resolve_var <name> <root> -> value on stdout, empty when undefined.
#
# `name` is the bare variable name, without the leading `$`, as apptype.lua
# spells it:
#
#   name = read_option("file", "fallback")   options/file, else the fallback,
#                                            exactly as the Lua reads it
#   name = "value"                           the literal
hypr_resolve_var() {
    local line
    line=$(_hypr_apptype_line "$1" "$2") || return 0
    if [[ $line =~ read_option\(\"([^\"]+)\"(,[[:space:]]*\"([^\"]*)\")? ]]; then
        option "$2/options/${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}"
    elif [[ $line =~ =[[:space:]]*\"([^\"]*)\" ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    fi
}
