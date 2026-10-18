#!/bin/bash
#
# What the sound popover needs and Quickshell's PipeWire bindings cannot do:
# move a stream to another output (or back to the default) and read which
# streams are pinned. Prints JSON on stdout; a failure exits 1 with
# {"ok":false,"error":"<message>"}.
#
#   route <serial> <sink-name>   pactl move-sink-input: pin the stream
#   route <serial> default       un-pin: the stream follows the default sink
#   pins                         {"<object id>":"<target.object>", ...}
#   pins --watch                 {} at once, then the whole map as one line
#                                after every monitor line (the initial replay
#                                included) that changes it, until killed;
#                                the last line is always the current state
#
# A stream is addressed by its Pulse index, which is its object.serial; the
# pins map is keyed by its PipeWire object id. Object ids are reused across
# streams, serials are not, hence `route` refuses a serial no current sink
# input has. Un-pinning writes target.object -1 rather than removing the key,
# so -1 means unpinned and never appears in a map. A stream that ends
# produces "remove: id:<n> all keys" in the monitor output.
#
# SOUND_PACTL and SOUND_PW_METADATA name the binaries, for tests.

set -euo pipefail

PACTL="${SOUND_PACTL:-pactl}"
PW_METADATA="${SOUND_PW_METADATA:-pw-metadata}"

# fail <message> — the error as JSON, then exit 1. Without jq it can only be
# the fixed jq message, which needs no escaping.
fail() {
    if command -v jq >/dev/null 2>&1; then
        jq -cn --arg e "$1" '{ok: false, error: $e}'
    else
        printf '{"ok":false,"error":"%s"}\n' "$1"
    fi
    exit 1
}

# need <label> <binary> — fail unless the binary can run.
need() { command -v "$2" >/dev/null 2>&1 || fail "$1 is required"; }

usage() {
    echo "usage: ${0##*/} route <serial> <sink-name|default> | pins [--watch]" >&2
    exit 2
}

declare -A pins=()
monitor_pid=""

# print_pins — the whole map as one JSON line, keys sorted.
print_pins() {
    local id
    for id in "${!pins[@]}"; do printf '%s\n%s\n' "$id" "${pins[$id]}"; done |
        jq -cnRS '[inputs] as $a | reduce range(0; $a | length; 2) as $i ({}; .[$a[$i]] = $a[$i + 1])'
}

# apply_line <metadata line> — fold one line into the map; succeeds only when
# the map changed.
apply_line() {
    local id value
    if [[ $1 =~ ^update:\ id:([0-9]+)\ key:\'target\.object\'\ value:\'(-?[0-9]+)\' ]]; then
        id=${BASH_REMATCH[1]} value=${BASH_REMATCH[2]}
        if [ "$value" = -1 ]; then
            [[ -v pins[$id] ]] || return 1
            unset "pins[$id]"
        else
            [ "${pins[$id]-}" != "$value" ] || return 1
            pins[$id]=$value
        fi
    elif [[ $1 =~ ^remove:\ id:([0-9]+)\ all\ keys ]]; then
        id=${BASH_REMATCH[1]}
        [[ -v pins[$id] ]] || return 1
        unset "pins[$id]"
    else
        return 1
    fi
}

# stream_exists <serial> — a sink input with that index is playing now.
stream_exists() {
    [[ $1 =~ ^[0-9]+$ ]] || return 1
    "$PACTL" -f json list sink-inputs | jq -e --argjson n "$1" 'any(.[]; .index == $n)' >/dev/null
}

# sink_exists <name> — a sink with that name is present now.
sink_exists() {
    [[ $1 =~ ^[A-Za-z0-9._:-]+$ ]] || return 1
    "$PACTL" -f json list sinks | jq -e --arg n "$1" 'any(.[]; .name == $n)' >/dev/null
}

cmd_route() {
    [ $# -eq 2 ] || usage
    local serial=$1 target=$2
    need pactl "$PACTL"; need jq jq
    stream_exists "$serial" || fail "No such stream: $serial"
    if [ "$target" = default ]; then
        target=@DEFAULT_SINK@
    else
        sink_exists "$target" || fail "No such output: $target"
    fi
    "$PACTL" move-sink-input "$serial" "$target" >/dev/null 2>&1 || fail "Could not move stream $serial"
    echo '{"ok":true}'
}

cmd_pins() {
    local watch=0
    case "${1-}" in
        "") ;;
        --watch) watch=1 ;;
        *) usage ;;
    esac
    [ $# -le 1 ] || usage
    need pw-metadata "$PW_METADATA"; need jq jq
    if ((watch)); then pins_watch; else pins_once; fi
}

# pins_once — one dump, one map.
pins_once() {
    local dump line
    dump=$("$PW_METADATA" -n default 2>/dev/null) || fail "Could not read routing metadata"
    while IFS= read -r line; do apply_line "$line" || true; done <<<"$dump"
    print_pins
}

# pins_watch — the monitor is the only source: it replays the current state
# and then streams changes, so no removal can fall between a dump and a
# subscription. The replay's end is not marked, so the start state is {} and
# the replay arrives as ordinary changes.
pins_watch() {
    local fd line
    exec {fd}< <("$PW_METADATA" -n default -m)
    monitor_pid=$!
    trap '[ -z "$monitor_pid" ] || kill "$monitor_pid" 2>/dev/null || true' EXIT
    trap 'exit 0' INT TERM
    print_pins
    while IFS= read -r line <&"$fd"; do
        if apply_line "$line"; then print_pins; fi
    done
    wait "$monitor_pid" || fail "Could not read routing metadata"
}

case "${1-}" in
    route) shift; cmd_route "$@" ;;
    pins) shift; cmd_pins "$@" ;;
    *) usage ;;
esac
