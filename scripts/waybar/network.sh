#!/bin/bash
#
# Network readout for Waybar: the combined download + upload rate while the
# machine is actually moving data (options/bar-network can instead show it
# always, or never), "Offline" when no physical interface holds a default
# route, and nothing at all otherwise. The module appearing is the notice --
# the same stateless grammar custom/updates and custom/battery use.
#
# Why not Waybar's own network module: its auto-detection follows the default
# route with the lowest metric, and Proton VPN installs an IPv6 default route
# (metric 95) through its ipv6leakintrf0 dummy, which is always "linked". The
# module tracked that dummy, so it could never report Offline and its tooltip
# never rendered. Its "interface" option matches `e*` but not `[ew]*`, so no
# one pattern names both wired and Wi-Fi. Here the interface is chosen by what
# it is -- backed by hardware (/sys/class/net/X/device) and holding a default
# route -- so no tunnel or dummy can stand in for it. A bridge over the NIC
# has no device link either; on such a host this would read Offline.
#
# Continuous: Waybar starts it once and takes one line per update. A tick is
# bash builtins only -- routes and counters come from /proc, the pause is a
# read timeout, elapsed time is $EPOCHREALTIME -- so sampling every two
# seconds spawns nothing. The one external command, `ip` for the tooltip's
# address, runs when the interface changes and once a minute after that. A
# line is printed only when it differs from the last, so an idle bar is not
# redrawn at all.
#
# NET_SYSFS and NET_PROC re-root the reads; that seam is how test-network.sh
# runs without hardware. Sourcing the file defines the functions without
# starting the loop.
#
# Glyphs are \U escapes: Nerd Font private-use characters vanish when retyped.
#

NET_SYSFS=${NET_SYSFS:-/sys/class/net}
NET_PROC=${NET_PROC:-/proc/net}
NET_INTERVAL=${NET_INTERVAL:-2}
# Bytes per second, up and down combined, before the readout appears. Background
# chatter -- sync clients, the VPN keepalive -- stays well below it.
NET_SHOW=${NET_SHOW:-102400}
# Quiet ticks before the readout hides again, so a download that stalls for a
# moment does not make the module blink.
NET_LINGER=${NET_LINGER:-3}
NET_QUIET=$NET_LINGER
# The Bar page's mode (options/bar-network): traffic (the rate only while data
# moves), always, or offline (never the rate). Offline itself shows in every
# mode. NET_MODE overrides the file for the tests.
BAR_OPTIONS="${BAR_OPTIONS:-$HOME/.config/options}"
if [ -z "${NET_MODE+set}" ]; then
    NET_MODE=''
    read -r NET_MODE 2>/dev/null < "$BAR_OPTIONS/bar-network"
fi
# Ticks between re-sends of an unchanged line. A closed stdout is only noticed
# on a write, so an idle bar re-sends once a minute to find out.
NET_BEAT=${NET_BEAT:-30}

NET_GLYPH_DOWN=$'\U000f01da'
NET_GLYPH_UP=$'\U000f0552'
NET_GLYPH_RATE=$'\U000f04e2'
NET_GLYPH_WIRED=$'\U000f0200'
NET_GLYPH_WIFI=$'\U000f0928'
NET_GLYPH_OFFLINE=$'\U000f0c9b'

# net_physical <iface> -- true for an interface backed by hardware
net_physical() {
    [ -e "$NET_SYSFS/$1/device" ]
}

# net_iface -- REPLY = the physical interface holding a default route, or
# empty. IPv4 first: /proc/net/route marks a default route by destination and
# mask 00000000. IPv6 default routes are ::/0 in /proc/net/ipv6_route.
net_iface() {
    local iface dest len mask _
    REPLY=
    if [ -r "$NET_PROC/route" ]; then
        while read -r iface dest _ _ _ _ _ mask _; do
            [ "$dest" = 00000000 ] && [ "$mask" = 00000000 ] || continue
            if net_physical "$iface"; then REPLY=$iface; return; fi
        done < "$NET_PROC/route"
    fi
    if [ -r "$NET_PROC/ipv6_route" ]; then
        while read -r dest len _ _ _ _ _ _ _ iface; do
            [ "$dest" = 00000000000000000000000000000000 ] && [ "$len" = 00 ] || continue
            if net_physical "$iface"; then REPLY=$iface; return; fi
        done < "$NET_PROC/ipv6_route"
    fi
}

# net_counters <iface> -- RX and TX = the interface's byte counters.
# /proc/net/dev writes "  eno1: 123" or, once the count is wide, "eno1:123";
# splitting on the colon as well as whitespace reads both.
net_counters() {
    local name rx tx _
    RX='' TX=''
    while IFS=$' \t:' read -r name rx _ _ _ _ _ _ _ tx _; do
        if [ "$name" = "$1" ]; then RX=$rx TX=$tx; return 0; fi
    done < "$NET_PROC/dev"
    return 1
}

# net_vpn -- REPLY = the first WireGuard or tun interface that is not down
net_vpn() {
    local dir line state
    REPLY=
    for dir in "$NET_SYSFS"/*; do
        [ -d "$dir" ] || continue
        [ -e "$dir/tun_flags" ] || {
            line=''
            while read -r line; do
                [ "$line" = DEVTYPE=wireguard ] && break
            done 2>/dev/null < "$dir/uevent"
            [ "$line" = DEVTYPE=wireguard ]
        } || continue
        state=''
        read -r state 2>/dev/null < "$dir/operstate"
        [ "$state" = down ] && continue
        REPLY=${dir##*/}
        return
    done
}

# net_address <iface> -- REPLY = its IPv4 address, else its first global IPv6
net_address() {
    local _ family addr
    REPLY=
    while read -r _ _ family addr _; do
        REPLY=${addr%/*}
        [ "$family" = inet ] && return
    done < <(ip -o addr show dev "$1" scope global 2>/dev/null)
}

# net_human <bytes/s> -- REPLY = the rate with its unit: "820 KB/s",
# "1.2 MB/s", "12.4 MB/s", "150 MB/s", "1.1 GB/s". One decimal below 100 of
# a unit, whole units from there. Unpadded, like the percentages beside it:
# padding would sit between the glyph and the number and pull the pair apart.
net_human() {
    local b=$1 div unit tenths
    if (( b < 1000 * 1024 )); then
        REPLY="$(( b / 1024 )) KB/s"
        return
    elif (( b < 1000 * 1048576 )); then
        div=1048576 unit='MB/s'
    else
        div=1073741824 unit='GB/s'
    fi
    tenths=$(( b * 10 / div ))
    # 1000 KiB/s is 0.98 MiB/s: show it as 1.0 of the larger unit, not 0.9,
    # so a rising rate never reads as a drop where the unit switches.
    (( tenths < 10 )) && tenths=10
    if (( tenths < 1000 )); then
        REPLY="$(( tenths / 10 )).$(( tenths % 10 )) $unit"
    else
        REPLY="$(( b / div )) $unit"
    fi
}

# net_visible <rx> <tx> -- true while the readout should show. A combined rate
# at or above NET_SHOW shows it at once; NET_LINGER quiet ticks hide it again.
net_visible() {
    if (( $1 + $2 >= NET_SHOW )); then
        NET_QUIET=0
    elif (( NET_QUIET < NET_LINGER )); then
        NET_QUIET=$(( NET_QUIET + 1 ))
    fi
    (( NET_QUIET < NET_LINGER ))
}

# net_escape <text> -- REPLY = text safe inside both Pango markup and a JSON
# string. Interface names are nearly free-form to the kernel -- control
# characters included, which JSON forbids raw, so they are dropped. The
# replacements are quoted: bash 5.2 otherwise reads a bare & in one as the
# matched text.
net_escape() {
    REPLY=${1//[[:cntrl:]]/}
    REPLY=${REPLY//&/'&amp;'}
    REPLY=${REPLY//</'&lt;'}
    REPLY=${REPLY//>/'&gt;'}
    # shellcheck disable=SC1003 # a literal backslash, not an escaped quote
    REPLY=${REPLY//\\/'\\'}
    REPLY=${REPLY//\"/'\"'}
}

# net_render <iface> <rx/s> <tx/s> <address> <vpn> -- OUT = the JSON line
net_render() {
    local iface=$1 rx=$2 tx=$3 addr=$4 vpn=$5 glyph text='' tooltip breakdown=''
    if [ -z "$iface" ]; then
        NET_QUIET=$NET_LINGER
        OUT="{\"text\":\"<span size='large'>$NET_GLYPH_OFFLINE</span>  Offline\",\"tooltip\":\"No wired or Wi-Fi connection\",\"class\":\"offline\"}"
        return
    fi
    local show=''
    case $NET_MODE in
        always)  show=1 ;;
        offline) ;;
        *)       net_visible "$rx" "$tx" && show=1 ;;
    esac
    if [ -n "$show" ]; then
        net_human $(( rx + tx ))
        # No space after the glyph, only 6pt letter spacing. cpu/memory/disk
        # use a space plus 4pt, but their glyphs fill their advance;
        # swap_vertical is narrow and centred, and the space left it 13px
        # from the digit. 6pt lands the gap at the 4-5px the others show,
        # measured in a rendered bar.
        text="<span size='large' letter_spacing='6144'>$NET_GLYPH_RATE</span>$REPLY"
        net_human "$rx"; breakdown="$NET_GLYPH_DOWN $REPLY   "
        net_human "$tx"; breakdown+="$NET_GLYPH_UP $REPLY\\n"
    fi
    glyph=$NET_GLYPH_WIRED
    [ -d "$NET_SYSFS/$iface/wireless" ] && glyph=$NET_GLYPH_WIFI
    net_escape "$iface"; tooltip="$breakdown$glyph  $REPLY"
    [ -n "$addr" ] && { net_escape "$addr"; tooltip+="  $REPLY"; }
    [ -n "$vpn" ] && { net_escape "$vpn"; tooltip+="\\nVPN  $REPLY"; }
    OUT="{\"text\":\"$text\",\"tooltip\":\"$tooltip\",\"class\":\"active\"}"
}

# net_orphaned <parent> -- true once this process has been re-parented, i.e.
# Waybar is gone. A closed stdout is only noticed on a write, and an idle or
# offline bar writes nothing new, so the loop checks this every tick; the
# NET_BEAT re-send covers a reader that closes while its process lives on.
net_orphaned() {
    local _ ppid
    read -r _ _ _ ppid _ < /proc/$BASHPID/stat 2>/dev/null || return 0
    [ "$ppid" != "$1" ]
}

net_main() {
    local tick current='' addr='' age=0 last='' now prev_t='' prev_rx=0 prev_tx=0 rx=0 tx=0 beat=0
    local parent=$PPID
    # A read on a pipe nobody writes is the pause: it times out without
    # spawning sleep. The <(:) is the only fork, once, at startup.
    exec {tick}<> <(:)
    while :; do
        net_iface
        if [ "$REPLY" != "$current" ]; then
            current=$REPLY prev_t='' age=0
        fi
        rx=0 tx=0
        if [ -n "$current" ]; then
            # Once a minute at the default interval: DHCP can renew the
            # address under an interface that never changed.
            if (( age % 30 == 0 )); then net_address "$current"; addr=$REPLY; fi
            age=$(( age + 1 ))
            if net_counters "$current"; then
                now=${EPOCHREALTIME//[!0-9]/}
                if [ -n "$prev_t" ] && (( now > prev_t && RX >= prev_rx && TX >= prev_tx )); then
                    rx=$(( (RX - prev_rx) * 1000000 / (now - prev_t) ))
                    tx=$(( (TX - prev_tx) * 1000000 / (now - prev_t) ))
                fi
                prev_t=$now prev_rx=$RX prev_tx=$TX
            fi
        fi
        net_vpn
        net_render "$current" "$rx" "$tx" "$addr" "$REPLY"
        beat=$(( beat + 1 ))
        if [ "$OUT" != "$last" ] || (( beat >= NET_BEAT )); then
            # Waybar closing the pipe is the signal to stop.
            printf '%s\n' "$OUT" || exit 0
            last=$OUT beat=0
        fi
        read -r -t "$NET_INTERVAL" -u "$tick" _
        net_orphaned "$parent" && exit 0
    done
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    net_main
fi
