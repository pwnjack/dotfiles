#!/bin/bash
#
# Resolution of application names referenced by the Lua configuration.
#
# Anything that reads a config line afterwards has to resolve the application
# table the same way. Two things do:
# the doctor's binary check, which needs to know the command a keybind really
# runs, and the keybinds cheatsheet, which labels `$terminal` with the terminal
# you actually use. One copy means a new variable source is taught once.
#
# Sourced, never executed. It defines functions and nothing else, so sourcing
# it twice in one shell is harmless.
#

# shellcheck source=scripts/lib/options.sh
. "${BASH_SOURCE[0]%/*}/options.sh"

# hypr_var_origin <name> -> `options` or `apptype`.
#
# Which of the two sources below defines the variable. Split out so the list of
# options-backed names exists once: hypr_resolve_var needs it to know where to
# read, and the cheatsheet's markdown mode needs it to know which values are a
# per-user preference rather than a repo constant. A second copy of this list
# would be a second source of truth.
hypr_var_origin() {
    case "$1" in
        terminal|browser|editor|codeeditor|filemanager) printf 'options' ;;
        *)                                              printf 'apptype' ;;
    esac
}

# hypr_resolve_var <name> <root> -> value on stdout, empty when undefined.
#
# `name` is the bare variable name, without the leading `$`. Two sources, in
# the order the config itself establishes them:
#
#   terminal, browser, editor,  apptype.lua reads options/<name> at parse
#   codeeditor, filemanager     time, so the option file is the value.
#   everything else             hypr/config/apptype.lua, `name = "value"`.
#
# Comments are stripped at the first `#`, which is Hyprland's own rule.
hypr_resolve_var() {
    local name="$1" root="$2" value=""

    case "$(hypr_var_origin "$name")" in
        options)
            value=$(option "$root/options/$name")
            ;;
        *)
            if [ -f "$root/hypr/config/apptype.lua" ]; then
                value="$(sed -n "s/^[[:space:]]*${name}[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" \
                    "$root/hypr/config/apptype.lua" | head -n1)"
            fi
            ;;
    esac

    # Trim surrounding whitespace.
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}
