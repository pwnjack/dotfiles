#!/bin/bash
# Every control a pointer can press says what it is to a screen reader. In
# each app file, the pointer areas (MouseArea, TapHandler) must not outnumber
# the items that carry an Accessible.role; an area that is not a control (it
# swallows clicks, closes on a click outside, or only tracks hover) is marked
# `// a11y: not a control` on the line that opens it.
# shortcut: counts per file and does not tie a role to its area, upgrade to a
# QML parser if a named file ever hides an unnamed control.
set -uo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/assert.sh
. "$here/../scripts/lib/assert.sh"

for file in "$here"/*/*.qml; do
    [ -L "$file" ] && continue
    areas=$(grep -o -E '\<(MouseArea|TapHandler)[[:space:]]*\{' "$file" | wc -l)
    [ "$areas" -gt 0 ] || continue
    plain=$(grep -c 'a11y: not a control' "$file")
    roles=$(grep -c -E 'Accessible\.role[[:space:]]*:' "$file")
    name=${file#"$here"/}
    [ $((areas - plain)) -le "$roles" ]
    check "$name: $areas pointer areas, $plain not controls, $roles roles"
done

test_summary accessible
