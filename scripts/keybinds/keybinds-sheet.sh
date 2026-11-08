#!/bin/bash
#
# Keybinds sheet
#
# Renders hypr/config/software/keybinds.lua for the Super+H keybindings overlay
# and for docs/keybindings.md, so neither can disagree with the bindings it
# documents. It used to be a hand-written printf block, and it had drifted: it
# advertised a mouse-scroll workspace bind that does not exist, omitted every
# silent-move binding, and named Ghostty and Zen in text while the binds
# resolved $terminal and $browser from options/.
#
# Usage: keybinds-sheet.sh --print|--markdown|--json
#   --print      aligned plain text, for a quick look in a terminal
#   --markdown   markdown tables, for docs/keybindings.md
#   --json       {"sections":[{"name","rows":[{"keys":[...],"label"}]}]},
#                read by quickshell/keybinds-overlay
#
# How a line becomes a row:
#
#   * `-- ## Heading` starts a section; sections with no rows are dropped.
#   * A trailing `--` comment is the label. `$vars`
#     inside it are resolved through scripts/lib/hypr-vars.sh, the same
#     resolution the doctor's binary check uses.
#   * Without a comment the Lua dispatcher expression becomes the label, so a
#     new binding always produces a row rather than disappearing silently.
#   * Rows sharing a section, option set, modifier set and label are
#     folded into one, with their keys listed together.
#
# The keysym table below is display vocabulary, not a second target list: an
# entry missing from it degrades to the raw keysym rather than a wrong row.
#
set -uo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$self_dir/../.." && pwd)"

# shellcheck source=../lib/hypr-vars.sh
source "$root/scripts/lib/hypr-vars.sh"

# KEYBINDS_CONF is the test seam: test-keybinds-sheet.sh points it at a fixture.
conf="${KEYBINDS_CONF:-$root/hypr/config/software/keybinds.lua}"

# Read before the parse, because it changes how labels are built rather than
# only how they are printed -- see _expand_vars.
mode="${1:-}"

case "$mode" in
    --print|--markdown|--json) ;;
    *)
        echo "Usage: keybinds-sheet.sh --print|--markdown|--json" >&2
        exit 2
        ;;
esac

if [ ! -f "$conf" ]; then
    echo "keybinds-sheet: no keybinds at $conf" >&2
    exit 1
fi

# _trim <string> -> the string without leading or trailing whitespace.
_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# _squeeze <string> -> runs of whitespace collapsed to one space, then trimmed.
# Only used on labels whose `%s` was substituted away.
_squeeze() {
    local s="$1"
    while [[ "$s" == *"  "* ]]; do s="${s//  / }"; done
    _trim "$s"
}

# _key_display <keysym> -> how that key is written on a keyboard.
# Everything unlisted passes through, which covers letters, digits and Fn keys.
_key_display() {
    case "$1" in
        RETURN|Return|KP_Enter) printf 'Enter' ;;
        SPACE|space)            printf 'Space' ;;
        ESCAPE|Escape)          printf 'Esc' ;;
        TAB|Tab)                printf 'Tab' ;;
        EQUAL|equal)            printf '=' ;;
        MINUS|minus)            printf '-' ;;
        period)                 printf '.' ;;
        comma)                  printf ',' ;;
        slash)                  printf '/' ;;
        BACKSPACE)              printf 'Backspace' ;;
        mouse:272)              printf 'Left button' ;;
        mouse:273)              printf 'Right button' ;;
        mouse_up)               printf 'Wheel up' ;;
        mouse_down)             printf 'Wheel down' ;;
        left|right|up|down)     local k="$1"; printf '%s' "${k^}" ;;
        # Media keys carry their legend, not their keysym: nobody's keyboard
        # says "AudioRaiseVolume".
        XF86AudioRaiseVolume)   printf 'Volume Up' ;;
        XF86AudioLowerVolume)   printf 'Volume Down' ;;
        XF86AudioMute)          printf 'Mute' ;;
        XF86AudioMicMute)       printf 'Mic Mute' ;;
        XF86AudioPlay)          printf 'Play' ;;
        XF86AudioPause)         printf 'Pause' ;;
        XF86AudioNext)          printf 'Next' ;;
        XF86AudioPrev)          printf 'Previous' ;;
        XF86*)                  printf '%s' "${1#XF86}" ;;
        *)                      printf '%s' "$1" ;;
    esac
}

# _mods_display <raw-mods> -> "Super + Shift", or empty for an unmodified bind.
_mods_display() {
    local out="" token value
    for token in $1; do
        value="$token"
        value="${value,,}"
        out="${out:+$out + }${value^}"
    done
    printf '%s' "$out"
}

# _expand_vars <text> -> text with every $var replaced by its resolved value.
# This is what lets `# Terminal ($terminal)` read "Terminal (ghostty)".
#
# Markdown mode deliberately does NOT resolve the options-backed variables.
# The overlay is read by the person whose options/ it just read, so naming
# their terminal is exactly right; docs/keybindings.md is committed and read by
# everyone, where "ghostty" would freeze one machine's preference into the repo
# as though it were fixed. Naming the file instead is true on every checkout,
# and it is what the reader has to edit anyway. Variables from apptype.lua are
# tracked config and identical on every checkout, so those still resolve.
_expand_vars() {
    local text="$1" out="" name value rest
    while [[ "$text" =~ ^([^$]*)\$([A-Za-z_][A-Za-z0-9_]*)(.*)$ ]]; do
        name="${BASH_REMATCH[2]}"
        rest="${BASH_REMATCH[3]}"
        if [ "$mode" = "--markdown" ] && [ "$(hypr_var_origin "$name")" = "options" ]; then
            value="\`options/$name\`"
        else
            value="$(hypr_resolve_var "$name" "$root")"
        fi
        out="$out${BASH_REMATCH[1]}${value:-\$$name}"
        text="$rest"
    done
    printf '%s%s' "$out" "$text"
}

# _format_keys <key>... -> the key column's list of keys.
# Three or more consecutive digits collapse to a range, and the full set of
# arrow keys collapses to the word every keyboard prints on them.
_format_keys() {
    local -a keys=("$@") out=()
    local n=${#keys[@]} i j k sep

    if [ "$n" -eq 4 ]; then
        local sorted
        sorted="$(printf '%s\n' "${keys[@]}" | sort | tr '\n' ' ')"
        if [ "$sorted" = "Down Left Right Up " ]; then
            printf 'Arrows'
            return
        fi
    fi

    # Pairs that read as one key whatever order the binds are written in:
    # both wheel directions are the wheel, and play/pause is one media key.
    if [ "$n" -eq 2 ]; then
        local pair
        pair="$(printf '%s\n' "${keys[@]}" | sort | tr '\n' ' ')"
        case "$pair" in
            "Wheel down Wheel up ") printf 'Wheel'; return ;;
            "Pause Play ")          printf 'Play/Pause'; return ;;
        esac
    fi

    i=0
    while [ "$i" -lt "$n" ]; do
        # Extend j over the longest ascending run of single digits from i.
        j=$i
        while [ $((j + 1)) -lt "$n" ] \
            && [[ "${keys[j]}" =~ ^[0-9]$ ]] \
            && [[ "${keys[j+1]}" =~ ^[0-9]$ ]] \
            && [ "${keys[j+1]}" -eq $(( keys[j] + 1 )) ]; do
            j=$((j + 1))
        done
        if [ $((j - i)) -ge 2 ]; then
            out+=("${keys[i]}-${keys[j]}")
        else
            # Too short to be worth a range: list the keys individually.
            for ((k = i; k <= j; k++)); do
                out+=("${keys[k]}")
            done
        fi
        i=$((j + 1))
    done

    # Two keys read as alternatives; longer lists read as a set.
    [ "${#out[@]}" -eq 2 ] && sep="/" || sep=", "
    local first=1 item
    for item in "${out[@]}"; do
        [ "$first" -eq 1 ] && first=0 || printf '%s' "$sep"
        printf '%s' "$item"
    done
}

# Record separators: \x1f between the fields of a fold key, \x1e between the
# keys accumulated into one row. Both are outside anything a config can hold.
US=$'\x1f'
RS=$'\x1e'

declare -A ROW_SECTION=() ROW_MODS=() ROW_KEYS=() ROW_DESC=()
declare -a ORDER=()

# Binds above the first `## Heading` still need a section a reader can name.
section="Other"
while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^[[:space:]]*--[[:space:]]*##[[:space:]]+(.*)$ ]]; then
        section="$(_trim "${BASH_REMATCH[1]}")"
        continue
    fi

    [[ "$line" =~ ^[[:space:]]*hl\.bind\(\"([^\"]+)\" ]] || continue
    keyspec="${BASH_REMATCH[1]}"
    key="${keyspec##* + }"
    if [ "$key" = "$keyspec" ]; then
        mods=""
    else
        mods="${keyspec% + *}"
        mods="${mods// + / }"
    fi
    [ -n "$key" ] || continue

    comment=""
    [[ "$line" == *") -- "* ]] && comment="$(_trim "${line##*) -- }")"
    if [ -n "$comment" ]; then
        desc="$(_expand_vars "$comment")"
    else
        action="${line#*hl.dsp.}"
        action="${action%%(*}"
        desc="$(_squeeze "${action//./ }")"
    fi

    bindtype="bind"
    [[ "$line" == *"mouse = true"* ]] && bindtype="bindm"
    [[ "$line" == *"locked = true"* ]] && bindtype="${bindtype}l"
    [[ "$line" == *"repeating = true"* ]] && bindtype="${bindtype}e"

    sig="$section$US$bindtype$US$mods$US$desc"
    if [ -z "${ROW_DESC[$sig]+set}" ]; then
        ORDER+=("$sig")
        ROW_SECTION[$sig]="$section"
        ROW_MODS[$sig]="$(_mods_display "$mods")"
        ROW_KEYS[$sig]="$(_key_display "$key")"
        ROW_DESC[$sig]="$desc"
    else
        ROW_KEYS[$sig]="${ROW_KEYS[$sig]}$RS$(_key_display "$key")"
    fi
done < "$conf"

# Two passes: the first settles the key column's width so the descriptions
# line up, the second prints. Both walk ORDER, so file order is preserved.
# MODS and KEYTXT keep the combo's parts apart for the JSON skin.
declare -a COMBOS=() LABELS=() SECTIONS=() MODS=() KEYTXT=()
width=0
for sig in "${ORDER[@]}"; do
    IFS="$RS" read -r -a keys <<< "${ROW_KEYS[$sig]}"
    keytxt="$(_format_keys "${keys[@]}")"
    combo="$keytxt"
    [ -n "${ROW_MODS[$sig]}" ] && combo="${ROW_MODS[$sig]} + $combo"
    combo="  $combo"

    COMBOS+=("$combo")
    LABELS+=("${ROW_DESC[$sig]}")
    SECTIONS+=("${ROW_SECTION[$sig]}")
    MODS+=("${ROW_MODS[$sig]}")
    KEYTXT+=("$keytxt")
    [ "${#combo}" -gt "$width" ] && width="${#combo}"
done

render() {
    local i prev="" first=1
    for i in "${!COMBOS[@]}"; do
        if [ "${SECTIONS[i]}" != "$prev" ]; then
            [ "$first" -eq 1 ] || printf '\n'
            printf '%s\n' "${SECTIONS[i]^^}"
            prev="${SECTIONS[i]}"
            first=0
        fi
        printf '%-*s  %s\n' "$width" "${COMBOS[i]}" "${LABELS[i]}"
    done
}

# Markdown skin over the same ORDER walk render() uses, so docs/keybindings.md
# and the overlay come from one parse and cannot disagree. Only the
# presentation differs: sections become `##` headings, the padding render()
# needs for a monospace list is dropped, and a table replaces the columns.
render_markdown() {
    local i prev="" combo label
    for i in "${!COMBOS[@]}"; do
        if [ "${SECTIONS[i]}" != "$prev" ]; then
            [ -n "$prev" ] && printf '\n'
            printf '## %s\n\n| Key | Action |\n|-----|--------|\n' "${SECTIONS[i]}"
            prev="${SECTIONS[i]}"
        fi
        # A `|` in either column would end the cell early. Neither the key
        # display table nor any current label produces one, but labels come
        # from config comments, so escaping is the difference between a new
        # comment being rendered and it quietly breaking the table.
        combo="$(_trim "${COMBOS[i]}")"
        label="${LABELS[i]}"
        printf '| `%s` | %s |\n' "${combo//|/\\|}" "${label//|/\\|}"
    done
}

# _json_str <text> -> REPLY holds the text as a JSON string literal. It sets a
# variable rather than printing because render_json calls it a few hundred
# times, and a command substitution forks on every call. Labels come from
# config comments, so quotes and backslashes must not end the string early.
_json_str() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"
    s="${s//[[:cntrl:]]/}"
    REPLY="\"$s\""
}

# JSON skin over the same ORDER walk, for quickshell/keybinds-overlay. Keys are
# a list: each modifier, then the formatted key, so the overlay draws one cap
# per part without re-parsing "Super + Shift + Q".
render_json() {
    local i prev="" open=0 row_sep="" key_sep rest
    printf '{"sections":['
    for i in "${!COMBOS[@]}"; do
        if [ "$open" -eq 0 ] || [ "${SECTIONS[i]}" != "$prev" ]; then
            if [ "$open" -eq 1 ]; then printf ']},'; fi
            _json_str "${SECTIONS[i]}"
            printf '{"name":%s,"rows":[' "$REPLY"
            prev="${SECTIONS[i]}"
            open=1
            row_sep=""
        fi
        printf '%s{"keys":[' "$row_sep"
        row_sep=","
        key_sep=""
        rest="${MODS[i]}"
        while [ -n "$rest" ]; do
            _json_str "${rest%% + *}"
            printf '%s%s' "$key_sep" "$REPLY"
            key_sep=","
            if [[ "$rest" == *" + "* ]]; then rest="${rest#* + }"; else rest=""; fi
        done
        _json_str "${KEYTXT[i]}"
        printf '%s%s],"label":' "$key_sep" "$REPLY"
        _json_str "${LABELS[i]}"
        printf '%s}' "$REPLY"
    done
    if [ "$open" -eq 1 ]; then printf ']}'; fi
    printf ']}\n'
}

case "$mode" in
    --print)    render ;;
    --markdown) render_markdown ;;
    --json)     render_json ;;
esac
