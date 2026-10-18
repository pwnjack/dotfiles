#!/bin/bash
#
# Every wireless peripheral on the machine as one JSON array -- the single
# reader behind the Waybar battery module, its low-battery notification and
# the settings panel's Devices page, so the three can never disagree.
#
# One row per physical device, from three sources:
#   power_supply  SCOPE=Device nodes: a battery the kernel can read. CAPACITY
#                 is a percentage; xone reports only CAPACITY_LEVEL.
#   USB/BT input  an input device whose physical device holds no such battery:
#                 a receiver whose peripheral reports nothing (the CX dongle
#                 of an Epomaker keyboard). SCOPE=System batteries are the
#                 machine's own and stay with battery.sh. "BT" is classic
#                 Bluetooth (an hciN:M connection); BLE HID arrives through
#                 uhid with neither parent, so a battery-less BLE device has
#                 no row -- its battery, when it reports one, still does.
#   headsetcontrol  USB headsets, whose battery only it can read.
#
# kind comes from udev's input classification, never from product names. A
# gaming mouse also exposes a keyboard interface and a keyboard receiver a
# mouse one, so an input tagged keyboard WITHOUT mouse is what makes a
# keyboard.
#
# alert is the one definition of "low" for every consumer. A sleeping device
# keeps its last reading (ONLINE=0 is the only honest field), so it never
# alerts.
#
# DEVICES_SYSFS, DEVICES_SUPPLY and DEVICES_UDEV move the roots for tests;
# DEVICES_HEADSETCONTROL swaps in a stand-in binary.

SYSFS=$(readlink -f "${DEVICES_SYSFS:-/sys}") || exit 1
SUPPLY="${DEVICES_SUPPLY:-$SYSFS/class/power_supply}"
UDEV="${DEVICES_UDEV:-/run/udev/data}"
LOW=25
CRITICAL=10

# Every input device once: resolved path and its udev ID_INPUT_* tags.
declare -a in_path=() in_tags=()
shopt -s nullglob
for link in "$SYSFS"/class/input/input*; do
    path=$(readlink -f "$link") || continue
    tags=$(sed -n 's/^E:ID_INPUT_\([A-Z]*\)=1$/\1/p' "$UDEV/+input:${link##*/}" 2>/dev/null | tr '\n' ' ')
    in_path+=("$path"); in_tags+=(" $tags")
done

# kind_of <device dir> — classify from the inputs underneath it.
kind_of() {
    local dir=$1 i joystick=0 keyboard=0 mouse=0
    for i in "${!in_path[@]}"; do
        [[ ${in_path[i]} == "$dir"/* ]] || continue
        [[ ${in_tags[i]} == *" JOYSTICK "* ]] && joystick=1
        [[ ${in_tags[i]} == *" MOUSE "* ]] && mouse=1
        [[ ${in_tags[i]} == *" KEYBOARD "* && ${in_tags[i]} != *" MOUSE "* ]] && keyboard=1
    done
    if ((joystick)); then echo gamepad
    elif ((keyboard)); then echo keyboard
    elif ((mouse)); then echo mouse
    else echo other; fi
}

# usb_of <path> — one Bluetooth connection, otherwise the nearest USB device.
usb_of() {
    local dir=$1
    while [[ $dir == "$SYSFS"/devices/* ]]; do
        [[ ${dir##*/} =~ ^hci[0-9]+:[0-9]+$ ]] && { printf '%s' "$dir"; return; }
        [ -f "$dir/idVendor" ] && { printf '%s' "$dir"; return; }
        dir=${dir%/*}
    done
}

rows=""   # tab-separated: id name kind percent level charging state [usb]
declare -A held=()   # USB devices already represented by a battery row

for uevent in "$SUPPLY"/*/uevent; do
    [ -r "$uevent" ] || continue
    dir=${uevent%/uevent}
    type="" scope="" cap="" level="" online="" model="" status=""
    while IFS='=' read -r key val; do
        case "$key" in
            POWER_SUPPLY_TYPE) [ -n "$type" ] || type=$val ;;
            POWER_SUPPLY_SCOPE) scope=$val ;;
            POWER_SUPPLY_CAPACITY) cap=$val ;;
            POWER_SUPPLY_CAPACITY_LEVEL) level=${val,,} ;;
            POWER_SUPPLY_ONLINE) online=$val ;;
            POWER_SUPPLY_MODEL_NAME) model=$val ;;
            POWER_SUPPLY_STATUS) status=$val ;;
        esac
    done < "$uevent"
    [ "$type" = Battery ] && [ "$scope" = Device ] || continue
    case "$cap" in ''|*[!0-9]*) cap="" ;; esac
    [ -n "$cap" ] || [ -n "$level" ] || continue
    kind=other
    if [ -e "$dir/device" ]; then
        device=$(readlink -f "$dir/device")
        kind=$(kind_of "$device")
        usb=$(usb_of "$device"); [ -n "$usb" ] && held[$usb]=1
    fi
    state=connected; [ "$online" = 0 ] && state=asleep
    charging=false; [ "$status" = Charging ] && charging=true
    model=${model//$'\n'/ }
    rows+="${dir##*/}"$'\t'"${model//$'\t'/ }"$'\t'"$kind"$'\t'"$cap"$'\t'"$level"$'\t'"$charging"$'\t'"$state"$'\n'
done

# Headsets report their battery over a vendor HID protocol the kernel does not
# speak, so they never get a power_supply node; headsetcontrol speaks it, and
# without it there are simply no headset rows. Each headset is matched to its
# dongle by USB id, which names the row and keeps the dongle out of the
# receiver rows below. Only devices that can report a battery count. A
# headset that is switched off, times out or errors comes back "partial" with
# level -1 (headsetcontrol's "no level") and is asleep, like a sleeping mouse.
# --timeout keeps headsetcontrol's own HID wait (5 s by default) inside the
# 2 s hard stop, so a silent headset still reports itself as timed out.
# DEVICES_HEADSETCONTROL names the binary; empty disables the source.
HEADSETCONTROL=${DEVICES_HEADSETCONTROL-headsetcontrol}
if [ -n "$HEADSETCONTROL" ] && command -v "$HEADSETCONTROL" >/dev/null 2>&1; then
    declare -A unmatched=()
    # Every field is non-empty: a tab-delimited read collapses empty fields.
    while IFS=$'\t' read -r vid pid name status level; do
        usb=""
        for dev in "$SYSFS"/bus/usb/devices/*; do
            [ -r "$dev/idVendor" ] && [ -r "$dev/idProduct" ] || continue
            [ "$(<"$dev/idVendor")" = "$vid" ] && [ "$(<"$dev/idProduct")" = "$pid" ] || continue
            dev=$(readlink -f "$dev") || continue
            [ -z "${held[$dev]:-}" ] || continue
            usb=$dev; break
        done
        if [ -n "$usb" ]; then
            held[$usb]=1; id=${usb##*/}
        else
            id="headset-$vid-$pid" n=1
            while [ -n "${unmatched[$id]:-}" ]; do n=$((n + 1)); id="headset-$vid-$pid-$n"; done
            unmatched[$id]=1
        fi
        case "$level" in *[!0-9]*) level="" ;; esac
        if [ -n "$level" ] && [[ $status == BATTERY_AVAILABLE || $status == BATTERY_CHARGING ]]; then
            charging=false; [ "$status" = BATTERY_CHARGING ] && charging=true
            rows+="$id"$'\t'"$name"$'\theadset\t'"$level"$'\t\t'"$charging"$'\tconnected\t'"$vid:$pid"$'\n'
        else
            rows+="$id"$'\t'"$name"$'\theadset\t\t\tfalse\tasleep\t'"$vid:$pid"$'\n'
        fi
    done < <(timeout -k 1 2 "$HEADSETCONTROL" --timeout 1000 -b -o json 2>/dev/null | jq -r '
        .devices[]? | select(.status == "success" or .status == "partial")
        | select(.capabilities // [] | index("CAP_BATTERY_STATUS")) | [
            (.id_vendor // "" | ltrimstr("0x") | ascii_downcase | if . == "" then "-" else . end),
            (.id_product // "" | ltrimstr("0x") | ascii_downcase | if . == "" then "-" else . end),
            (.device // .product // "" | gsub("[\t\n]"; " ") | if . == "" then "Headset" else . end),
            (.battery.status // "BATTERY_UNAVAILABLE"),
            (.battery.level // -1 | tostring)
        ] | join("\t")' 2>/dev/null)
fi

declare -A seen=()
for i in "${!in_path[@]}"; do
    usb=$(usb_of "${in_path[i]}")
    [ -n "$usb" ] || continue
    [ -z "${held[$usb]:-}" ] && [ -z "${seen[$usb]:-}" ] || continue
    seen[$usb]=1
    kind=$(kind_of "$usb")
    [ "$kind" = other ] && continue
    name=""
    if [ -r "$usb/product" ]; then
        name=$(head -n1 "$usb/product")
    else
        for j in "${!in_path[@]}"; do
            [[ ${in_path[j]} == "$usb"/* ]] || continue
            name=$(head -n1 "${in_path[j]}/name" 2>/dev/null)
            break
        done
    fi
    name=${name//$'\n'/ }
    rows+="${usb##*/}"$'\t'"${name//$'\t'/ }"$'\t'"$kind"$'\t\t\tfalse\treceiver\n'
done

printf '%s' "$rows" | jq -R -n --argjson low "$LOW" --argjson critical "$CRITICAL" '
    [inputs | split("\t") | {
        id: (.[0] | gsub("[^A-Za-z0-9._-]"; "_")), name: (if .[1] == "" then .[0] else .[1] end), kind: .[2],
        percent: (if .[3] == "" then null else (.[3] | tonumber) end),
        level: (if .[4] == "" then null else .[4] end),
        charging: (.[5] == "true"), state: .[6]
    } + (if (.[7] // "") != "" then {usb: .[7]} else {} end) | .alert = (
        if .state != "connected" then "none"
        elif ((.percent != null and .percent < $critical) or .level == "critical") then "critical"
        elif ((.percent != null and .percent < $low) or .level == "low") then "low"
        else "none" end)]
    | (map(select(.state != "receiver")) | sort_by(.id)) + (map(select(.state == "receiver")) | sort_by(.id))'
