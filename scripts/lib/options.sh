#!/bin/bash
#
# The one reader of a preference in options/ (docs/internals/options.md).
# Sourced, never executed. It defines a function and nothing else.
#

# option <file> [fallback] -> the file's first line, surrounding whitespace
# (a CRLF line's \r included) trimmed; the fallback (default empty) when the
# file is missing or unreadable or that line is empty. Always returns 0, so a
# caller under `set -e` does not abort on a missing file.
option() {
    local value=''
    { IFS= read -r value < "$1"; } 2>/dev/null || true
    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    printf '%s' "${value:-${2-}}"
}
