#!/bin/bash
#
# Config reference integrity: every path a tracked file points at must exist.
#
# Nothing is enumerated here. The conf and Lua files to walk come from git, the
# source/require targets come out of those files, the
# literal ~/.config paths come out of every tracked file, and wall.sh's optional
# colour scripts come out of wall.sh's own loop header. A config added tomorrow
# is covered the moment it is committed.
#
# The listings are read NUL-delimited (-z). Without it git renders a path
# holding a quote or a non-ASCII byte as a C-quoted string ("\303\274..."),
# which no longer names a file on disk and would be misreported as missing.
#
# WHAT IS DELIBERATELY NOT REPORTED:
#
#   docs/ and *.md — plans, specs and READMEs cite illustrative paths that are
#   meant not to exist. Scanning them buries every real finding.
#
#   scripts/doctor/ — same reason, one level up. The check modules argue for
#   their own design in prose that has to name example paths, and the test
#   fixtures are built entirely out of paths chosen for not existing. Without
#   this the doctor's loudest finding is itself: sixteen errors, every one of
#   them a line in its own test file.
#
#   Tracked symlinks. In this repo a tracked symlink always points into
#   ~/.cache, so its content is written by the palette hooks or waypaper, not by
#   this repo. A dangling reference in there is not something the user can fix
#   by editing the repo — and the obvious hint, "drop the reference from
#   waypaper/config.ini", would tell them to edit a cache file that waypaper
#   rewrites on next launch. The symlinks check already covers the link itself.
#
#   Any path still holding a $variable or a glob. It names a set, possibly
#   empty, rather than one file, so "does not exist" is not a claim that can be
#   made about it. The extraction pattern therefore deliberately swallows $, *,
#   ?, [ and ] so such a path is captured whole and then skipped — truncating
#   it at the first special character would leave a prefix that looks checkable
#   and produce a false positive.
#
#   Paths outside the tree under test (a bare /etc/... source target). There is
#   nothing under DOCTOR_ROOT to compare them against.
#
# SEVERITY. ERROR means the session is broken or breaks on next login; WARN
# means a feature is degraded. That line falls between the two kinds of
# reference this check finds:
#
#   A missing `source =` or require() target is an ERROR. The owning Hypr
#   program loses that module — keybinds, rules, monitors, or lock styling.
#
#   Missing generated Hyprland/Hyprlock palettes are ERRORs: their links dangle.
#   Missing slots or roles are WARNs: palette.sh supplies fallback colours.
#
#   A missing literal ~/.config/... reference is a WARN. A script or config
#   pointing at a file that is not there breaks that one feature when it is
#   invoked; the session still comes up. Calling it an ERROR would make
#   doctor.sh exit 1 on a healthy machine, which is how a health check teaches
#   its user to ignore the exit code.
#
# wall.sh's colour fan-out is a WARN for a second, independent reason: the
# script guards each entry with `[ -x "$script" ]` and documents them as
# optional, so a missing one is expected rather than merely survivable. It
# keeps its own wording and fix hint — pointing at the loop to edit rather than
# at a stray reference — and the distinction is worth keeping even though both
# now land on the same severity, so that re-tightening literal references
# later cannot silently sweep the deliberately-optional ones up with them.
# That list is lifted from wall.sh's `for ... in ... ; do` header rather than
# matched by filename, so the waybar entry — which is not an
# apply_wal_colors.sh — is covered too.
#
# DOCTOR_ROOT is assumed to be a git work tree; doctor.sh establishes that once
# via doctor_require_repo, so an empty listing here means "no configs", not "no
# repository".
#
# Accepted limitations:
#   - Inline comments are stripped from a source line at the first #, so a
#     target legitimately containing # would be truncated. Hyprland has no
#     escape for it either.
#   - A reference reachable two ways (hypr/hyprland.lua's require call and a
#     script's literal $HOME/.config/hypr/... path) is
#     reported once per referrer. Both findings are true and each names a
#     different file to fix.
#   - The extraction pattern has no way to express a space, so a referenced
#     path containing one is truncated at the space and may be reported as
#     missing. No such reference exists in this repo, and quoting conventions
#     in the configs make one unlikely.
#   - A ~/.config/../ reference resolves outside DOCTOR_ROOT. It is only ever
#     stat'ed, never written, and no such reference exists in practice.
#   - If wall.sh ever stops iterating its colour scripts in a `for` loop the
#     optional list comes back empty and those paths fall through to the
#     generic literal-reference wording. Same severity, less specific hint.
#

# Cache root, overridable so the test suite can point at a throwaway directory
# instead of the user's real palette output.
DOCTOR_CACHE="${DOCTOR_CACHE:-$HOME/.cache}"

# The shape of a literal reference into this repo, as written in a config or a
# script. The bracket expression leads with ][ so both brackets are literal.
# Braces are accepted only as a whole ${name}: a lone } is the end of an
# enclosing ${VAR:-~/.config/x} default, not part of the path.
DOCTOR_REF_PATTERN='(\$HOME|~)/\.config/([][A-Za-z0-9._/$*?-]|\$\{[A-Za-z0-9_]+\})+'

# _ref_under_root <path>
# Prints the DOCTOR_ROOT-relative form of a literal ~/.config reference.
# Returns 1 if the path does not name something inside the tree under test.
#
# The prefix is stripped by an explicitly quoted, anchored pattern rather than
# by ${path#*/.config/}: a glob strip would also fire on the /.config/ buried
# inside a path like ~/.config/scripts/x/.config/y. Shortest-match happens to
# get that one right, but only by accident of the anchor, and longest-match
# would silently rewrite it to "y" — a finding pointing at the wrong file.
_ref_under_root() {
    # Both prefixes are data, not paths: they are the two spellings a config
    # file writes down, and expanding either would defeat the comparison.
    # SC2088 assumes a leading tilde was meant to expand.
    # shellcheck disable=SC2088
    case "$1" in
        '$HOME/.config/'*) printf '%s' "${1#'$HOME/.config/'}" ;;
        '~/.config/'*)     printf '%s' "${1#'~/.config/'}" ;;
        *) return 1 ;;
    esac
}

# _ref_unresolvable <root-relative-path>
# True when the path still holds a variable or a glob, so no single file can be
# expected to match it.
_ref_unresolvable() {
    case "$1" in
        ''|*'$'*|*'*'*|*'?'*|*'['*) return 0 ;;
    esac
    return 1
}

# _ref_extract_paths <file>
# Every distinct literal ~/.config reference in a file. -I skips binary files,
# which would otherwise contribute a "Binary file ... matches" line.
_ref_extract_paths() {
    grep -IoE "$DOCTOR_REF_PATTERN" "$1" 2>/dev/null | sort -u
}

# _ref_source_targets <file>
# The right-hand side of every `source =` line, with any inline comment and
# trailing whitespace removed.
_ref_source_targets() {
    sed -n 's/^[[:space:]]*source[[:space:]]*=[[:space:]]*//p' "$1" 2>/dev/null \
        | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//'
}

# _ref_require_targets <file>
# Lua modules are dot-separated and resolved from the hypr/ configuration root.
_ref_require_targets() {
    sed -nE 's/.*require\("([A-Za-z0-9_.-]+)"\).*/\1/p' "$1" 2>/dev/null
}

# _ref_wall_optional
# wall.sh's existence-guarded colour fan-out, one path per line, taken from the
# loop header that iterates it.
_ref_wall_optional() {
    local wall="$DOCTOR_ROOT/scripts/hyprland/wall.sh"
    [ -f "$wall" ] || return 0
    sed -n '/^[[:space:]]*for[[:space:]].*[[:space:]]in/,/do$/p' "$wall" 2>/dev/null \
        | grep -IoE "$DOCTOR_REF_PATTERN"
}

# _ref_check_sources — Hyprland source chains.
# A source target is resolved against the sourcing file's own directory, which
# is how Hyprland reads it. The base is derived from the conf's path, so a conf
# that moves keeps working and one at the top of the tree does not produce a
# doubled slash.
_ref_check_sources() {
    local conf base target rel full

    # Process substitution, not a pipeline — see the contract note in lib.sh.
    while IFS= read -r -d '' conf; do
        case "$conf" in
            docs/*|scripts/doctor/*|*.md) continue ;;
        esac
        [ -f "$DOCTOR_ROOT/$conf" ] || continue
        [ -L "$DOCTOR_ROOT/$conf" ] && continue

        base="${conf%/*}"
        if [ "$base" = "$conf" ]; then
            base=""
        else
            base="$base/"
        fi

        while IFS= read -r target; do
            [ -n "$target" ] || continue

            if ! rel="$(_ref_under_root "$target")"; then
                case "$target" in
                    /*|'~'*) continue ;;
                esac
                rel="$base$target"
            fi
            _ref_unresolvable "$rel" && continue

            full="$DOCTOR_ROOT/$rel"
            [ -e "$full" ] && continue

            err "$conf sources $target, which does not exist" \
                "restore $(doctor_q "$full"), or drop the source line from $(doctor_q "$DOCTOR_ROOT/$conf")"
        done < <(_ref_source_targets "$DOCTOR_ROOT/$conf")
    done < <(git -C "$DOCTOR_ROOT" ls-files -z -- '*.conf' 2>/dev/null)
}

# _ref_check_requires — Hyprland's Lua module chain.
_ref_check_requires() {
    local lua module rel full

    while IFS= read -r -d '' lua; do
        [ -f "$DOCTOR_ROOT/$lua" ] || continue
        [ -L "$DOCTOR_ROOT/$lua" ] && continue

        while IFS= read -r module; do
            [ -n "$module" ] || continue
            rel="hypr/${module//./\/}.lua"
            full="$DOCTOR_ROOT/$rel"
            [ -e "$full" ] && continue
            err "$lua requires $module, but $rel does not exist" \
                "restore $(doctor_q "$full"), or drop the require from $(doctor_q "$DOCTOR_ROOT/$lua")"
        done < <(_ref_require_targets "$DOCTOR_ROOT/$lua")
    done < <(git -C "$DOCTOR_ROOT" ls-files -z -- 'hypr/*.lua' 'hypr/**/*.lua' 2>/dev/null)
}

# _ref_check_literals — literal ~/.config paths anywhere in the tracked tree.
_ref_check_literals() {
    local wall="scripts/hyprland/wall.sh" optional
    local file path rel full

    optional="$(_ref_wall_optional)"

    while IFS= read -r -d '' file; do
        case "$file" in
            docs/*|scripts/doctor/*|*.md) continue ;;
        esac
        [ -f "$DOCTOR_ROOT/$file" ] || continue
        [ -L "$DOCTOR_ROOT/$file" ] && continue

        while IFS= read -r path; do
            rel="$(_ref_under_root "$path")" || continue
            _ref_unresolvable "$rel" && continue

            full="$DOCTOR_ROOT/$rel"
            [ -e "$full" ] && continue

            if [ "$file" = "$wall" ] && printf '%s\n' "$optional" | grep -qxF -- "$path"; then
                warn "$wall applies colours via ~/.config/$rel, which is missing" \
                     "restore $(doctor_q "$full"), or remove it from the list in $(doctor_q "$DOCTOR_ROOT/$wall")"
            else
                warn "$file references ~/.config/$rel, which does not exist" \
                     "restore $(doctor_q "$full"), or drop the reference from $(doctor_q "$DOCTOR_ROOT/$file")"
            fi
        done < <(_ref_extract_paths "$DOCTOR_ROOT/$file")
    done < <(git -C "$DOCTOR_ROOT" ls-files -z 2>/dev/null)
}

# _ref_check_palette_cache — the generator's slots and roles, and the generated
# outputs Hyprland's colors.lua and Hyprlock's colors.conf resolve to. Name
# missing inputs directly as well as the symlinks that consume their outputs.
_ref_check_palette_cache() {
    local palette severity missing=0
    for palette in "$DOCTOR_CACHE/wal/colors" \
                   "$DOCTOR_CACHE/wal/roles" \
                   "$DOCTOR_CACHE/wal/colors-hyprland.conf" \
                   "$DOCTOR_CACHE/wal/colors-hyprland.lua"; do
        [ -e "$palette" ] && continue
        case "${palette##*/}" in
            colors|roles) severity=warn ;;
            *) severity=err ;;
        esac
        "$severity" "palette cache missing: $palette" \
            "change the wallpaper (Super+Ctrl+W), or run $(doctor_q "$DOCTOR_ROOT/scripts/theming/generate-palette.sh") $(doctor_q /path/to/wallpaper.jpg) && $(doctor_q "$DOCTOR_ROOT/scripts/theming/apply-wal.sh")"
        missing=1
    done
    return "$missing"
}

check_references() {
    group "Config references"

    local before_errors="$DOCTOR_ERRORS"
    local before_warnings="$DOCTOR_WARNINGS"
    local before_notices="$DOCTOR_NOTICES"

    _ref_check_sources
    _ref_check_requires
    _ref_check_literals
    _ref_check_palette_cache

    # ok is the all-clear and nothing else. Gating it on the error count alone
    # would print a green tick over a warning the reader is meant to act on.
    # Every finding names its own file, so there is nothing to summarise when
    # there are findings — and routing a summary through note would inflate the
    # notices tally with a line that is not a finding.
    if [ "$DOCTOR_ERRORS" -eq "$before_errors" ] &&
       [ "$DOCTOR_WARNINGS" -eq "$before_warnings" ] &&
       [ "$DOCTOR_NOTICES" -eq "$before_notices" ]; then
        ok "all config references resolve"
    fi
}
