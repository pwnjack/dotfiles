#!/bin/bash
#
# Battery status for waybar -- every battery on the machine, system or
# peripheral.
#
# waybar's own battery module counts only POWER_SUPPLY_SCOPE=System, which is
# why it logged "No batteries." on this desktop while a wireless mouse sat on
# the bus with a perfectly readable charge. System batteries use sysfs here;
# peripherals use scripts/devices/devices.sh, including level-only batteries.
#
# System batteries (SCOPE System or absent) are read from sysfs here and always
# shown. SCOPE=Device nodes are skipped: peripherals come from
# scripts/devices/devices.sh, which owns their sleep and alert rules. ONLINE
# present-and-0 still skips a node (a laptop battery has no ONLINE). Charge
# state suppresses the alert classes.
#
# BATTERY_SYSFS overrides the scan root; test-battery.sh points it at fixtures.
# BATTERY_ALERT_FIXTURE=1 enables alerts for those fixtures; tests must stub
# notify-send and set DEVICE_ALERT_STATE to an isolated temporary directory.
#

LOW=25
CRITICAL=10
SYSFS="${BATTERY_SYSFS:-/sys/class/power_supply}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Nerd Font, Material Design range.
ICON_SYSTEM=$'\U000f0079'    # battery
ICON_GAMEPAD=$'\U000f0297'   # gamepad
ICON_MOUSE=$'\U000f037d'     # mouse
ICON_KEYBOARD=$'\U000f030c'  # keyboard
ICON_HEADSET=$'\U000f02cb'   # headphones
ICON_DEVICE=$'\U000f0083'    # battery-alert, for a peripheral we cannot name

# Fields of the uevent currently being read.
u_type=""; u_cap=""; u_scope=""; u_online=""; u_model=""; u_status=""

# read_uevent <path> — parse one uevent into the u_* variables.
read_uevent() {
    local key val
    u_type=""; u_cap=""; u_scope=""; u_online=""; u_model=""; u_status=""
    while IFS='=' read -r key val; do
        case "$key" in
            # TYPE appears twice in a hidpp uevent. Keep the first.
            POWER_SUPPLY_TYPE)       [ -n "$u_type" ] || u_type="$val" ;;
            POWER_SUPPLY_CAPACITY)   u_cap="$val" ;;
            POWER_SUPPLY_SCOPE)      u_scope="$val" ;;
            POWER_SUPPLY_ONLINE)     u_online="$val" ;;
            POWER_SUPPLY_MODEL_NAME) u_model="$val" ;;
            POWER_SUPPLY_STATUS)     u_status="$val" ;;
        esac
    done < "$1"
}

# device_icon <model> — a glyph from the vendor string, which is all sysfs
# gives us. upower knows the real device type, but costs a daemon and a D-Bus
# round trip per device per poll; an unmatched device gets a generic battery
# glyph, which is unspecific rather than wrong.
device_icon() {
    case "${1,,}" in
        *mouse*)               printf '%s' "$ICON_MOUSE" ;;
        *keyboard*|*keypad*)   printf '%s' "$ICON_KEYBOARD" ;;
        *headset*|*headphone*) printf '%s' "$ICON_HEADSET" ;;
        *)                     printf '%s' "$ICON_DEVICE" ;;
    esac
}

# entry <icon> <value> — one rendered chunk of the bar text. The glyph is
# promoted a fifth to match the bar scale (14px base); see waybar/style.css.
#
# ONE space between glyph and value. This used to be two, on the argument that
# a battery glyph carries ink to the right and needed the wider spacer to look
# equal to its neighbours. Screenshotting the bar with this module forced
# visible (BATTERY_SYSFS, which is what that seam is for) showed the opposite:
# beside cpu/memory/gpu/disk the two-space entries read as visibly detached
# from their numbers.
# The gap BETWEEN entries stays wider -- see the joiner below -- so two
# batteries still read as two readouts rather than one run-on number.
entry() {
    printf '<span size="large">%s</span> %s' "$1" "$2"
}

declare -a system_text=()
# capacity driving the class; empty means "not alerting" -- unlike a
# sentinel number, no value CAPACITY can take (even a malformed one out of
# sysfs's normal 0-100 range) can ever be mistaken for "nothing is alerting".
system_worst=""
device_alert=none
declare -a low_text=()
declare -a tips=()

shopt -s nullglob
for uevent in "$SYSFS"/*/uevent; do
    [ -r "$uevent" ] || continue
    read_uevent "$uevent"

    [ "$u_type" = "Battery" ] || continue
    [ "$u_scope" = "Device" ] && continue

    # A missing or non-numeric capacity would make the arithmetic tests below
    # throw into waybar's log once every interval.
    case "$u_cap" in ''|*[!0-9]*) continue ;; esac

    # Present-and-0 only. See the header.
    [ "$u_online" = "0" ] && continue

    dir="${uevent%/uevent}"
    label="${u_model:-${dir##*/}}"

    # Accumulate, don't overwrite: dual-battery laptops are a real target,
    # and a second, healthier battery must never hide a nearly-flat one.
    system_text+=("$(entry "$ICON_SYSTEM" "$u_cap%")")
    case "$u_status" in
        # "Not charging" means AC is connected but something is inhibiting
        # the charge -- almost always a charge_control_end_threshold on a
        # ThinkPad or a Dell/ASUS platform module. The machine is on mains,
        # so however low the number is it is not an emergency, and treating
        # it as discharging would raise exactly the false alarm that
        # suppressing Charging exists to prevent.
        Charging|Full|"Not charging")
            tips+=("$label  $u_cap% ($u_status)")
            ;;
        *)
            tips+=("$label  $u_cap%")
            # Only a discharging system battery can raise an alert; take
            # the minimum across all of them so the worst one always wins.
            if [ -z "$system_worst" ] || [ "$u_cap" -lt "$system_worst" ]; then
                system_worst="$u_cap"
            fi
            ;;
    esac
done
shopt -u nullglob

# A fixture never asks a real headset, unless a test names a stand-in.
[ -n "${BATTERY_SYSFS+x}" ] && export DEVICES_HEADSETCONTROL="${DEVICES_HEADSETCONTROL-}"
devices=$(DEVICES_SUPPLY="$SYSFS" bash "$script_dir/../devices/devices.sh")
# Keep notification delivery outside Waybar's exec and close its output fds.
# Ordinary fixtures and forced screenshots never notify.
if [ -z "${BATTERY_SYSFS+x}" ] || [ "${BATTERY_ALERT_FIXTURE:-0}" = 1 ]; then
    bash "$script_dir/../devices/battery-alert.sh" <<<"$devices" >/dev/null 2>&1 &
fi
while IFS=$'\x1f' read -r name kind percent level alert; do
    if [ -n "$percent" ]; then value="$percent%"; else value="${level^}"; fi
    case "$kind" in
        gamepad) icon=$ICON_GAMEPAD ;;
        mouse) icon=$ICON_MOUSE ;;
        keyboard) icon=$ICON_KEYBOARD ;;
        headset) icon=$ICON_HEADSET ;;
        *) icon=$(device_icon "$name") ;;
    esac
    tips+=("$name  $value")
    [ "$alert" = none ] && continue
    low_text+=("$(entry "$icon" "$value")")
    if [ "$alert" = critical ] || [ "$device_alert" = none ]; then
        device_alert=$alert
    fi
done < <(jq -r '.[] | select(.state == "connected")
    | [.name, .kind, (.percent // ""), (.level // ""), .alert]
    | map(tostring | gsub("[\u001f\n]"; " ")) | join("\u001f")' <<<"$devices")

parts=("${system_text[@]}" "${low_text[@]}")

# Nothing worth saying: print nothing and let waybar hide the module, the same
# idiom custom/media uses.
[ "${#parts[@]}" -eq 0 ] && exit 0

class=ok
if [ "$device_alert" = critical ] || { [ -n "$system_worst" ] && [ "$system_worst" -lt "$CRITICAL" ]; }; then
    class=critical
elif [ "$device_alert" = low ] || { [ -n "$system_worst" ] && [ "$system_worst" -lt "$LOW" ]; }; then
    class=low
fi

# Three spaces BETWEEN entries, against the one inside each — see entry().
# The two gaps have to stay visibly different or "󰁹 64% 󰍽 18%" reads as one
# run-on number; the separator must be the wider of the two, not equal to it.
printf -v text '%s   ' "${parts[@]}"; text=${text%   }
printf -v tooltip '%s\n' "${tips[@]}"; tooltip=${tooltip%$'\n'}

# `text` is ours: glyphs and digits, no vendor string, so its markup is safe.
# `tooltip` carries model names, which are arbitrary vendor text -- "Corsair
# HS80 & Mouse" is malformed Pango and would blank the tooltip. Escape it.
jq -nc --arg text "$text" --arg tooltip "$tooltip" --arg class "$class" '
    def pango: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
    {text: $text, tooltip: ($tooltip | pango), class: $class}'
