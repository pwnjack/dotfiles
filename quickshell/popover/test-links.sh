#!/bin/bash
# Quickshell loads QML only from a config's own folder, so a card that names a
# shared type needs a link to it in its own directory. Without one the card
# fails at launch with "X is not a type", which no QML suite sees: none loads
# a shell.qml.
set -uo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/assert.sh
. "$here/../../scripts/lib/assert.sh"

for shared in "$here"/*.qml; do
    type=$(basename "$shared" .qml)
    users=0
    for app in "$here"/../*/; do
        [ "$app" -ef "$here" ] && continue
        grep -qE "^[[:space:]]*${type}[[:space:]]*\\{" "$app"*.qml 2>/dev/null || continue
        users=$((users + 1))
        name=$(basename "$app") # before the test: check reads the last status
        [ "$app$type.qml" -ef "$shared" ]
        check "$name links $type.qml"
    done
    [ "$users" -gt 0 ]
    check "$type.qml is used by a card"
done

test_summary popover
