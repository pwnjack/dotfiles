#!/bin/bash
# Tests for scripts/devices/devices.sh against a fake /sys and /run/udev/data.
set -uo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICES="$TEST_DIR/devices.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck disable=SC1091 # Shared assertions are checked by their own suite.
# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

root() { local r; r=$(mktemp -d "$TMP/root.XXXXXX"); mkdir -p "$r/sys/class/power_supply" "$r/sys/class/input" "$r/udev"; printf '%s' "$r"; }
# usb <root> <usbpath> <product> — a USB device dir (has idVendor)
usb() { mkdir -p "$1/sys/devices/$2"; echo 1234 > "$1/sys/devices/$2/idVendor"; echo "$3" > "$1/sys/devices/$2/product"; }
# input <root> <devpath> <n> <TAG>... — input device n under devpath, udev tags ID_INPUT_<TAG>=1
input() {
    local r=$1 dev=$2 n=$3; shift 3
    mkdir -p "$r/sys/devices/$dev/input/input$n"
    ln -s "../../devices/$dev/input/input$n" "$r/sys/class/input/input$n"
    { echo "E:ID_INPUT=1"; for t in "$@"; do echo "E:ID_INPUT_$t=1"; done; } > "$r/udev/+input:input$n"
}
# supply <root> <name> <devpath|-> <KEY=VALUE>... — a power_supply node, linked to devpath unless "-"
supply() {
    local r=$1 name=$2 dev=$3; shift 3
    mkdir -p "$r/sys/class/power_supply/$name"
    printf 'POWER_SUPPLY_%s\n' "$@" > "$r/sys/class/power_supply/$name/uevent"
    [ "$dev" = - ] || ln -s "../../../devices/$dev" "$r/sys/class/power_supply/$name/device"
}
run() { DEVICES_SYSFS="$1/sys" DEVICES_UDEV="$1/udev" bash "$DEVICES"; }
# Fixtures never ask a real headset; headset tests name a stand-in.
export DEVICES_HEADSETCONTROL=
mkdir -p "$TMP/bin"
cat > "$TMP/bin/headsetcontrol" <<'STUB'
#!/bin/sh
[ "$*" = "--timeout 1000 -b -o json" ] || exit 2
[ -n "${HC_SLEEP:-}" ] && sleep "$HC_SLEEP"
cat "$HC_JSON"
STUB
chmod +x "$TMP/bin/headsetcontrol"
# dongle <root> <usbpath> <vid> <pid> — a USB device listed on the USB bus
dongle() {
    usb "$1" "$2" "Headset Dongle"
    echo "$3" > "$1/sys/devices/$2/idVendor"; echo "$4" > "$1/sys/devices/$2/idProduct"
    mkdir -p "$1/sys/bus/usb/devices"
    ln -s "../../../devices/$2" "$1/sys/bus/usb/devices/${2##*/}"
}
# headset <status> <level> [device-status] [capability] [count] — headsetcontrol
# JSON for count identical G533s (one by default)
headset() {
    local one i out=""
    one=$(printf '{"status":"%s","device":"Logitech G533","id_vendor":"0x046d","id_product":"0x0A66","capabilities":["CAP_SIDETONE","%s"],"battery":{"status":"%s","level":%s}}' \
        "${3:-success}" "${4:-CAP_BATTERY_STATUS}" "$1" "$2")
    for ((i = 0; i < ${5:-1}; i++)); do out+="${out:+,}$one"; done
    printf '{"devices":[%s]}' "$out" > "$TMP/hc.json"
}
hc() { DEVICES_HEADSETCONTROL="$TMP/bin/headsetcontrol" HC_JSON="$TMP/hc.json" run "$@"; }
field() { jq -r --arg id "$2" ".[] | select(.id == \$id) | .$3" <<<"$1"; }

echo "devices.sh"

r=$(root)
usb "$r" usb1/1-14 "Lightspeed Receiver"
input "$r" usb1/1-14/1-14:1.2/hid.1/hid.2 19 MOUSE KEY KEYBOARD
supply "$r" hidpp_battery_0 usb1/1-14/1-14:1.2/hid.1/hid.2 TYPE=Battery SCOPE=Device ONLINE=1 CAPACITY=36 "MODEL_NAME=G Pro Wireless Gaming Mouse"
out=$(run "$r")
assert_eq "$(field "$out" hidpp_battery_0 kind)" mouse "a mouse with a keyboard interface is a mouse"
assert_eq "$(field "$out" hidpp_battery_0 percent)" 36 "percent is read"
assert_eq "$(field "$out" hidpp_battery_0 state)" connected "online battery is connected"
assert_eq "$(field "$out" hidpp_battery_0 alert)" none "36% does not alert"
assert_eq "$(jq length <<<"$out")" 1 "the receiver holding a battery is not listed again"

r=$(root)
supply "$r" m - TYPE=Battery SCOPE=Device ONLINE=0 CAPACITY=5 MODEL_NAME=Mouse
out=$(run "$r")
assert_eq "$(field "$out" m state)" asleep "ONLINE=0 is asleep"
assert_eq "$(field "$out" m alert)" none "a stale reading never alerts"
assert_eq "$(field "$out" m kind)" other "no device link means kind other"

r=$(root)
usb "$r" usb1/1-13 "Xbox Wireless Adapter"
input "$r" usb1/1-13/1-13:1.0/gip0/gip0.0 34 JOYSTICK KEY
supply "$r" gip0.0 usb1/1-13/1-13:1.0/gip0/gip0.0 TYPE=Battery SCOPE=Device STATUS=Discharging CAPACITY_LEVEL=Critical "MODEL_NAME=Microsoft Xbox Controller"
out=$(run "$r")
assert_eq "$(field "$out" gip0.0 kind)" gamepad "a joystick is a gamepad"
assert_eq "$(field "$out" gip0.0 percent)" null "level-only device has no percent"
assert_eq "$(field "$out" gip0.0 level)" critical "level is lowercased"
assert_eq "$(field "$out" gip0.0 alert)" critical "level Critical alerts critical"

for case in "18 low" "9 critical" "10 low" "25 none"; do
    read -r pct want <<<"$case"
    r=$(root); supply "$r" b - TYPE=Battery SCOPE=Device CAPACITY="$pct"
    assert_eq "$(field "$(run "$r")" b alert)" "$want" "$pct% alerts $want"
done
r=$(root); supply "$r" b - TYPE=Battery SCOPE=Device CAPACITY_LEVEL=Low
assert_eq "$(field "$(run "$r")" b alert)" low "level Low alerts low"
r=$(root); supply "$r" b - TYPE=Battery SCOPE=Device STATUS=Charging CAPACITY=50
assert_eq "$(field "$(run "$r")" b charging)" true "Charging is reported"

r=$(root)
usb "$r" usb1/1-8 "CX 2.4G Wireless Receiver"
input "$r" usb1/1-8/1-8:1.0/hid.1 3 KEY KEYBOARD
input "$r" usb1/1-8/1-8:1.1/hid.2 8 MOUSE
input "$r" usb1/1-8/1-8:1.1/hid.2 7 KEY
out=$(run "$r")
assert_eq "$(field "$out" 1-8 kind)" keyboard "a keyboard receiver with a mouse interface is a keyboard"
assert_eq "$(field "$out" 1-8 state)" receiver "no battery means receiver"
assert_eq "$(field "$out" 1-8 name)" "CX 2.4G Wireless Receiver" "receiver name is the USB product"
assert_eq "$(jq length <<<"$out")" 1 "one row per USB device"

r=$(root)
mkdir -p "$r/sys/devices/platform/btn"
input "$r" platform/btn 1 KEY KEYBOARD
usb "$r" usb1/1-4 "NZXT Kraken"
supply "$r" BAT0 - TYPE=Battery SCOPE=System CAPACITY=80
assert_eq "$(run "$r")" "[]" "non-USB inputs, input-less USB devices and system batteries are not listed"

r=$(root); supply "$r" b - TYPE=Battery SCOPE=Device CAPACITY=80 CAPACITY_LEVEL=Critical
assert_eq "$(field "$(run "$r")" b alert)" critical "critical level overrides a healthy percent"
r=$(root); supply "$r" b - TYPE=Battery SCOPE=Device CAPACITY=18 CAPACITY_LEVEL=Critical
assert_eq "$(field "$(run "$r")" b alert)" critical "critical level overrides a low percent"

# Bluetooth connections share a USB radio, but each is its own device.
r=$(root)
usb "$r" usb1/1-6 "Bluetooth Radio"
bt=usb1/1-6/1-6:1.0/bluetooth/hci0
input "$r" "$bt/hci0:1/0005:1234:0001.0001" 40 MOUSE
input "$r" "$bt/hci0:2/0005:1234:0002.0002" 41 KEY KEYBOARD
printf 'Bluetooth Keyboard\n' > "$r/sys/devices/$bt/hci0:2/0005:1234:0002.0002/input/input41/name"
supply "$r" bt_mouse "$bt/hci0:1/0005:1234:0001.0001" TYPE=Battery SCOPE=Device CAPACITY=50
out=$(run "$r")
assert_eq "$(jq length <<<"$out")" 2 "a Bluetooth battery does not hide another connection"
assert_eq "$(field "$out" hci0_2 name)" "Bluetooth Keyboard" "Bluetooth name comes from its HID input"
assert_eq "$(field "$out" hci0_2 kind)" keyboard "Bluetooth keyboard has its own classification"

r=$(root)
usb "$r" usb1/1-6 "Bluetooth Radio"
input "$r" "$bt/hci0:1/0005:1234:0001.0001" 40 MOUSE
input "$r" "$bt/hci0:2/0005:1234:0002.0002" 41 KEY KEYBOARD
printf 'Bluetooth Mouse\n' > "$r/sys/devices/$bt/hci0:1/0005:1234:0001.0001/input/input40/name"
out=$(run "$r")
assert_eq "$(jq -c 'map(.id)' <<<"$out")" '["hci0_1","hci0_2"]' "two battery-less Bluetooth connections stay separate"
assert_eq "$(field "$out" hci0_1 name)" "Bluetooth Mouse" "Bluetooth mouse uses its input name"
assert_eq "$(field "$out" hci0_2 name)" 'hci0:2' "missing input name falls back to connection basename"
assert_eq "$(DEVICES_SYSFS="$r/sys/" DEVICES_UDEV="$r/udev" bash "$DEVICES")" "$out" "trailing slash preserves device discovery"
ln -s "$r/sys" "$r/sys-link"
assert_eq "$(DEVICES_SYSFS="$r/sys-link" DEVICES_UDEV="$r/udev" bash "$DEVICES")" "$out" "symlinked sysfs preserves device discovery"

r=$(root)
usb "$r" usb1/1-5 "Media Gadget"
input "$r" usb1/1-5/hid.1 2 KEY
assert_eq "$(run "$r")" '[]' "media-key-only USB gadgets are excluded"

r=$(root)
supply "$r" z_battery - TYPE=Battery SCOPE=Device CAPACITY=50
supply "$r" a_battery - TYPE=Battery SCOPE=Device CAPACITY=40
usb "$r" usb1/1-9 "Later Receiver"
input "$r" usb1/1-9/hid.1 9 MOUSE
usb "$r" usb1/1-2 "Earlier Receiver"
input "$r" usb1/1-2/hid.2 2 KEYBOARD
assert_eq "$(run "$r" | jq -c 'map(.id)')" '["a_battery","z_battery","1-2","1-9"]' "sorted batteries precede sorted receivers"

r=$(root)
dongle "$r" usb1/1-2 046d 0a66
input "$r" usb1/1-2/1-2:1.3/hid.1 5 KEY KEYBOARD
headset BATTERY_AVAILABLE 80
out=$(hc "$r")
assert_eq "$(jq -c 'map(.id)' <<<"$out")" '["1-2"]' "a headset is named by its dongle and replaces the dongle's receiver row"
assert_eq "$(field "$out" 1-2 kind)" headset "a headsetcontrol device is a headset"
assert_eq "$(field "$out" 1-2 name)" "Logitech G533" "headset name is headsetcontrol's device"
assert_eq "$(field "$out" 1-2 percent)" 80 "headset percent is read"
assert_eq "$(field "$out" 1-2 state)" connected "a headset with a level is connected"
assert_eq "$(field "$out" 1-2 charging)" false "available is not charging"
assert_eq "$(field "$out" 1-2 usb)" "046d:0a66" "a headset row carries its USB id"

headset BATTERY_CHARGING 65
assert_eq "$(field "$(hc "$r")" 1-2 charging)" true "BATTERY_CHARGING is charging"
headset BATTERY_AVAILABLE 8
assert_eq "$(field "$(hc "$r")" 1-2 alert)" critical "a headset under 10% alerts critical"

# headsetcontrol 4.0's shape for a headset that is off, timed out or erroring.
headset BATTERY_UNAVAILABLE -1 partial
out=$(hc "$r")
assert_eq "$(field "$out" 1-2 state)" asleep "a partial headset without a level is asleep"
assert_eq "$(field "$out" 1-2 percent)" null "-1 is no level"
assert_eq "$(field "$out" 1-2 alert)" none "an asleep headset never alerts"
headset BATTERY_HIDERROR 40
assert_eq "$(field "$(hc "$r")" 1-2 state)" asleep "an error status ignores its level"

headset BATTERY_AVAILABLE 80 failure
assert_eq "$(jq -c 'map(.id)' <<<"$(hc "$r")")" '["1-2"]' "a failed headsetcontrol device leaves the plain receiver row"
assert_eq "$(field "$(hc "$r")" 1-2 kind)" keyboard "the dongle keeps its own classification"
headset BATTERY_UNAVAILABLE -1 success CAP_LIGHTS
assert_eq "$(field "$(hc "$r")" 1-2 kind)" keyboard "a device that cannot report a battery is not a headset row"

r=$(root)
headset BATTERY_AVAILABLE 50
assert_eq "$(jq -c 'map(.id)' <<<"$(hc "$r")")" '["headset-046d-0a66"]' "an unmatched headset is named by its USB id"
assert_eq "$(field "$(hc "$r")" headset-046d-0a66 usb)" "046d:0a66" "an unmatched headset carries its USB id too"
headset BATTERY_AVAILABLE 50 success CAP_BATTERY_STATUS 2
assert_eq "$(jq -c 'map(.id)' <<<"$(hc "$r")")" '["headset-046d-0a66","headset-046d-0a66-2"]' "identical unmatched headsets keep distinct ids"

r=$(root)
dongle "$r" usb1/1-3 046d 0a66
input "$r" usb1/1-3/1-3:1.2/hid.1 6 MOUSE
supply "$r" hidpp_battery_1 usb1/1-3/1-3:1.2/hid.1 TYPE=Battery SCOPE=Device CAPACITY=40
headset BATTERY_AVAILABLE 50
assert_eq "$(jq -c 'map(.id)' <<<"$(hc "$r")")" '["headset-046d-0a66","hidpp_battery_1"]' "a dongle already holding a battery is not claimed twice"

r=$(root)
supply "$r" m - TYPE=Battery SCOPE=Device CAPACITY=50
assert_eq "$(jq -r '[.[] | has("usb")] | any' <<<"$(run "$r")")" false "non-headset rows have no usb key"

r=$(root)
supply "$r" m - TYPE=Battery SCOPE=Device CAPACITY=50
printf 'not json' > "$TMP/hc.json"
assert_eq "$(jq -c 'map(.id)' <<<"$(DEVICES_HEADSETCONTROL="$TMP/bin/headsetcontrol" HC_JSON="$TMP/hc.json" run "$r")")" '["m"]' "unreadable headsetcontrol output adds nothing"
assert_eq "$(jq -c 'map(.id)' <<<"$(DEVICES_HEADSETCONTROL="$TMP/missing" run "$r")")" '["m"]' "a missing headsetcontrol adds nothing"
headset BATTERY_AVAILABLE 50
start=$SECONDS
out=$(HC_SLEEP=10 hc "$r")
assert_eq "$(jq -c 'map(.id)' <<<"$out")" '["m"]' "a hung headsetcontrol is abandoned"
if ((SECONDS - start < 5)); then pass "a hung headsetcontrol costs at most its timeout"; else fail "a hung headsetcontrol costs at most its timeout" "took $((SECONDS - start)) s"; fi

test_summary
