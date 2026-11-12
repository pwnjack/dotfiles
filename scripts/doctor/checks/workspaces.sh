#!/bin/bash
#
# Native Waybar modules (cffi/*): each one placed on the bar must resolve to a
# library that exists, and should not be older than its sources.
#
# Nothing is listed here. The placed modules come out of config.jsonc via
# waybar.sh's _way_placed (modules-* arrays and a group's nested "modules");
# module_path comes out of the includes that config.jsonc itself names
# (rendered by scripts/waybar/build-workspaces.sh, because Waybar passes
# module_path to dlopen verbatim and the tracked config cannot hold a home
# path). The include's "source" key is informational only -- where the library
# was built from; staleness is decided by build-workspaces.sh --check, which
# hashes the sources under $DOCTOR_ROOT.
#
# Requires waybar.sh to be sourced first (doctor.sh does).
#
# SEVERITY: a missing, relative or unset module_path, a missing library, or a
# --check that cannot run is an ERROR -- Waybar drops the module and the bar
# has no workspaces. A stale library is a WARN: the bar runs, just the previous
# build. The fix hint names build-workspaces.sh, the only builder of a cffi
# module in this repository.

# _wsm_home -- host probe, redefined by the tests
_wsm_home() { printf '%s' "$HOME"; }

# _wsm_current <lib> -- the build script's own content-hash comparison
# (build-workspaces.sh --check: builds and writes nothing). Redefined by tests.
# Returns 0 when current, 1 when stale or missing, and 2 when --check could
# not run at all (prints the script's first stderr line on stdout).
_wsm_current() {
    local out rc errf msg
    errf="$(mktemp)" || { echo "could not create a temporary file"; return 2; }
    out="$(WORKSPACES_LIB="$1" bash "$DOCTOR_ROOT/scripts/waybar/build-workspaces.sh" --check 2>"$errf")"
    rc=$?
    msg="$(head -n1 "$errf")"
    rm -f "$errf"
    if [ "$rc" -eq 0 ]; then
        return 0
    fi
    if [ "$rc" -eq 1 ] && grep -qE 'is (stale|missing)' <<< "$out"; then
        return 1
    fi
    [ -n "$msg" ] || msg="$(head -n1 <<< "$out")"
    [ -n "$msg" ] || msg="build-workspaces.sh --check exited $rc"
    printf '%s\n' "$msg"
    return 2
}

# _wsm_placed -- cffi/* names placed on the bar
_wsm_placed() {
    local config="$DOCTOR_ROOT/waybar/config.jsonc"
    [ -f "$config" ] || return 0
    _way_placed "$config" | grep '^cffi/' || true
}

# _wsm_includes -- the include paths config.jsonc names, in order, with a
# leading ~/ or $HOME/ expanded. Tracks the array like _way_placed, so one
# entry per line, comments and trailing commas all parse.
_wsm_includes() {
    local config="$DOCTOR_ROOT/waybar/config.jsonc" path home
    [ -f "$config" ] || return 0
    home="$(_wsm_home)"
    while IFS= read -r path; do
        # shellcheck disable=SC2016,SC2088  # literal "~/" and "$HOME/" prefixes on purpose
        case "$path" in
            "~/"*) path="$home/${path#\~/}" ;;
            '$HOME/'*) path="$home/${path#\$HOME/}" ;;
        esac
        printf '%s\n' "$path"
    done < <(awk '
        /^[[:space:]]*"include"[[:space:]]*:/ {
            # The string form ("include": "path",) names one file: take its
            # first string and stop, whatever follows on the line.
            line = $0
            sub(/\/\/.*$/, "", line)
            sub(/^[^:]*:/, "", line)
            if (index(line, "[") == 0) {
                if (match(line, /"[^"]*"/)) print substr(line, RSTART + 1, RLENGTH - 2)
                next
            }
            inarr = 1
        }
        inarr {
            line = $0
            sub(/\/\/.*$/, "", line)
            sub(/^[^:]*:/, "", line)
            while (match(line, /"[^"]*"/)) {
                print substr(line, RSTART + 1, RLENGTH - 2)
                line = substr(line, RSTART + RLENGTH)
            }
            if (index(line, "]")) inarr = 0
        }
    ' "$config")
}

# _wsm_main_sets <module> <key> -- succeeds when config.jsonc's own block for
# the module sets the key (Waybar lets the main config win over any include)
_wsm_main_sets() {
    local config="$DOCTOR_ROOT/waybar/config.jsonc"
    [ -f "$config" ] || return 1
    awk -v mod="$1" -v key="$2" '
        # // comments are stripped first: a commented-out entry is not a key.
        function hit(s) { sub(/\/\/.*$/, "", s); return index(s, "\"" key "\"") > 0 }
        inblk {
            if (hit($0)) { found = 1 }
            if ($0 ~ /^  }/) inblk = 0
            next
        }
        match($0, /^  "[^"]*"[[:space:]]*:[[:space:]]*\{/) {
            k = $0
            sub(/^  "/, "", k)
            sub(/".*$/, "", k)
            if (k != mod) next
            rest = $0
            sub(/^[^{]*\{/, "", rest)
            if (hit(rest)) found = 1
            if (index(rest, "}") == 0) inblk = 1
        }
        END { exit found ? 0 : 1 }
    ' "$config"
}

# _wsm_field <module> <key> -- the value from the FIRST include that sets it.
# Waybar's rule: the main config's own keys win, then the first include that
# sets a key; later includes never override it. (The main-config case is
# handled by _wsm_main_sets, not here.)
_wsm_field() {
    local module="$1" key="$2" file value
    while IFS= read -r file; do
        [ -f "$file" ] || continue
        value="$(jq -r --arg m "$module" --arg k "$key" '.[$m][$k] // empty' "$file" 2>/dev/null)" || continue
        if [ -n "$value" ]; then
            printf '%s' "$value"
            return 0
        fi
    done < <(_wsm_includes)
    return 0
}

check_workspaces() {
    group "Native Waybar modules"

    local before
    before=$(doctor_findings)
    local module lib build_hint detail rc
    build_hint="run $(doctor_q "$DOCTOR_ROOT/scripts/waybar/build-workspaces.sh")"

    while IFS= read -r module; do
        if _wsm_main_sets "$module" module_path; then
            err "$module: config.jsonc must not set module_path; Waybar needs an absolute path and the tracked config is host-neutral" \
                "remove module_path from the $module block in $(doctor_q "$DOCTOR_ROOT/waybar/config.jsonc")"
            continue
        fi
        lib="$(_wsm_field "$module" module_path)"
        if [ -z "$lib" ]; then
            err "$module is on the bar but no include gives its module_path; Waybar drops it" \
                "$build_hint"
            continue
        fi
        case "$lib" in
            /*) ;;
            *)
                err "$module module_path $(doctor_q "$lib") is not absolute; Waybar cannot dlopen it" \
                    "$build_hint"
                continue
                ;;
        esac
        if [ ! -f "$lib" ]; then
            err "$module library $(doctor_q "$lib") is missing; Waybar drops the module" \
                "$build_hint"
            continue
        fi
        rc=0
        detail="$(_wsm_current "$lib")" || rc=$?
        case "$rc" in
            0) ;;
            1)
                warn "$module library $(doctor_q "$lib") does not match its sources; the bar runs a previous build" \
                    "$build_hint, then restart Waybar"
                ;;
            *)
                err "$module library $(doctor_q "$lib") could not be checked: $detail" \
                    "$build_hint"
                ;;
        esac
    done < <(_wsm_placed)

    ok_if_clean "$before" "every placed native module is built and current"
}
