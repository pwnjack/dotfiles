#!/bin/bash
# Every control a pointer can press says what it is to a screen reader, and
# can be pressed through it. In each app file:
#   - the pointer areas (MouseArea, TapHandler) must not outnumber the items
#     with a control's role (a button, radio button, check box, list item,
#     link or slider); an area that is not a control (it swallows clicks,
#     closes on a click outside, only tracks hover or the wheel) carries
#     `// a11y: not a control` on the line that opens it;
#   - each pressable role has an Accessible.onPressAction, each slider an
#     Accessible.onIncreaseAction;
#   - every such action names `enabled`: Qt runs an accessible action on a
#     disabled item, and `enabled` reads false under a disabled ancestor too.
# shortcut: counts per file and does not tie a role to its area, upgrade to a
# QML parser if a file ever hides an unnamed control behind another's role.
set -uo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib/assert.sh
. "$here/../scripts/lib/assert.sh"

area='\<(MouseArea|TapHandler)[[:space:]]*(\{|$)'
action='Accessible\.on(Press|Toggle|Increase|Decrease)Action'
role='Accessible\.role[[:space:]]*:[[:space:]]*Accessible\.'
for file in "$here"/*/*.qml; do
    [ -L "$file" ] && continue
    areas=$(grep -o -E "$area" "$file" | wc -l)
    plain=$(grep -c -E "${area%(*}\{.*// a11y: not a control" "$file")
    pressable=$(grep -c -E "$role(Button|RadioButton|CheckBox|ListItem|Link)\>" "$file")
    sliders=$(grep -c -E "${role}Slider\>" "$file")
    [ $((areas + pressable + sliders)) -gt 0 ] || continue
    name=${file#"$here"/}
    [ $((areas - plain)) -le $((pressable + sliders)) ]
    check "$name: $areas pointer areas, $plain not controls, $((pressable + sliders)) controls"
    presses=$(grep -c 'Accessible\.onPressAction' "$file")
    steps=$(grep -c 'Accessible\.onIncreaseAction' "$file")
    [ "$pressable" -le "$presses" ] && [ "$sliders" -le "$steps" ]
    check "$name: $pressable pressable with $presses press actions, $sliders sliders with $steps step actions"
    unguarded=$(grep -E "$action" "$file" | grep -c -v 'enabled')
    [ "$unguarded" -eq 0 ]
    check "$name: $unguarded actions that ignore enabled"
done

test_summary accessible
