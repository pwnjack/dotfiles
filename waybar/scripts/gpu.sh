#!/bin/bash
#
# GPU usage + temperature for waybar.
#
# Emits JSON through jq rather than printf: the GPU name is vendor-supplied
# free text, and hand-built JSON breaks the module the day a name contains a
# quote. jq also lets the glyph stay an ASCII \u escape, so this file needs no
# Nerd Font installed to be edited safely.
#
# The glyph is wrapped in <span size='large'> to match the bar's scale: every
# module sits at 13px and promotes its glyph by 20%. See waybar/style.css.
#
# Usage: gpu.sh [WARNING CRITICAL]. The alert thresholds come from
# config.jsonc so they sit beside the cpu/memory/disk "states" -- waybar's
# custom modules ignore "states", so this script sets the class itself, and
# style.css colours .warning / .critical the same way for all four readouts.
#
# One nvidia-smi call, not five. The old version spawned the binary once per
# field, five times every 5s interval.
#

# The Bar page's mode (options/bar-gpu): always, high, or hidden. Read before
# nvidia-smi so a hidden module costs one file read, not a driver probe.
BAR_OPTIONS="${BAR_OPTIONS:-$HOME/.config/options}"
# shellcheck source=scripts/lib/options.sh
. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/options.sh"
mode=$(option "$BAR_OPTIONS/bar-gpu")
[ "$mode" = hidden ] && exit 0

command -v nvidia-smi >/dev/null 2>&1 || exit 0

read -r usage temp used total name < <(
    nvidia-smi \
        --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,name \
        --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ','
)

# No reading means no GPU to report. Stay silent so waybar hides the module
# rather than rendering a bare percent sign with nothing in front of it.
[ -z "$usage" ] && exit 0

# The same goes for a reading that is not a number: [N/A] from a GPU that
# does not report utilization, or the error text nvidia-smi prints on stdout
# when the driver is unreachable. Classifying either would call an unknown
# state healthy.
[[ $usage =~ ^[0-9]+$ ]] || exit 0

warning=${1:-70}
critical=${2:-90}
class=ok
if [ "$usage" -ge "$critical" ]; then class=critical
elif [ "$usage" -ge "$warning" ]; then class=warning
fi

# "high" shows the readout only once it is worth a colour.
[ "$mode" = high ] && [ "$class" = ok ] && exit 0

jq -nc \
    --arg usage "$usage" \
    --arg temp "$temp" \
    --arg name "$name" \
    --arg used "$used" \
    --arg total "$total" \
    --arg class "$class" \
    '{
        class: $class,
        text: ("<span size=\"large\" letter_spacing=\"4096\">\ue266</span> " + $usage + "%"),
        tooltip: ("GPU " + $usage + "% [" + $temp + "°C]\n\n" + $name
                  + "\nVRAM: " + $used + "MB / " + $total + "MB")
    }'
