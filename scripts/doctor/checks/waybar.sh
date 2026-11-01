#!/bin/bash
#
# Waybar bar integrity: every module on the bar is configured, every configured
# block is on the bar, and every command a handler invokes exists.
#
# Nothing is enumerated here. The placed modules come out of the modules-left,
# modules-center and modules-right arrays; the configured blocks come out of
# the file's own top-level keys; the commands come out of the handler values. A
# module added tomorrow is covered the moment it is committed.
#
# WHY GREP AND AWK RATHER THAN jq. config.jsonc is JSONC: jq fails on it
# outright (comments, trailing commas), and stripping comments first would
# corrupt any string containing // — a handler value can hold a URL. The file's
# own two-space top-level indent is a more reliable handle than a
# pre-processor. (_way_placed does strip //, but only inside a modules array,
# where every element is a bare module name; see the note there.)
#
# WHAT IS DELIBERATELY NOT REPORTED:
#
#   Handler paths under ~/.config or $HOME/.config. references.sh already scans
#   every tracked file for those, and config.jsonc is tracked, so checking them
#   here would report the same fact twice against the same file.
#
#   A built-in module placed with no config block is NOT an error. waybar
#   renders clock or cpu perfectly well on its defaults. It is still worth a
#   WARN, because it is also exactly what a typo looks like -- waybar drops an
#   unknown module name silently, so a bar missing a module looks identical to
#   a bar that never had one.
#
#   A style.css selector for every module. CSS selectors nest and group, so the
#   derivation is unreliable in a way the other two are not.
#
# SEVERITY:
#
#   A custom/* module placed with no block is an ERROR. It has no exec and no
#   format, so there is nothing for waybar to run or draw: the module is dead.
#
#   A built-in placed with no block is a WARN, per the note above.
#
#   A block placed in no modules list is INFO -- doctor.sh's header defines
#   that severity as exactly this ("tidiness -- orphaned config").
#
#   A missing handler binary is a WARN, matching references.sh: one broken
#   interaction is degradation, not a broken session, and calling it an ERROR
#   would make doctor.sh exit 1 on a machine whose bar comes up fine.
#
# Accepted limitations:
#   - A handler value containing an escaped quote is truncated at that quote.
#     No such value exists here.
#   - Only the first token of a handler is checked, so `sh -c "foo"` is checked
#     as `sh`. Checking deeper means parsing a shell command line out of JSON.
#   - The two-space indent rule assumes the file keeps its current formatting.
#     A reformat that changes top-level indentation makes the block list come
#     back empty, which shows up immediately as every placed module reported.
#   - A group/* module declares its children in a nested "modules": [...] that
#     _way_placed does not read, so every child's config block would come back
#     as a false orphan INFO. No group is used here (zero in the live config),
#     which is the only reason the claim above about tomorrow's module holds.
#

# Waybar's own action keywords. They sit exactly where a command would, and are
# NOT separable by module: wlr/taskbar uses "activate" and "close" in the same
# handler fields where custom modules place executable command lines.
#
# This is upstream waybar vocabulary, not a second source of truth for anything
# in this repo, so no change here can make it stale -- only a waybar release
# can. Both failure modes are bounded and visible: a keyword added upstream and
# used here produces one false WARN, and a binary genuinely named like a
# keyword hides one real finding.
#
# Space-padded at both ends so the membership test below is one `case` rather
# than three processes — the same idiom, for the same reason, as _BIN_SEEN in
# binaries.sh.
DOCTOR_WAYBAR_ACTIONS=" activate close minimize minimize-raise fullscreen mode shift_up shift_down shift_reset "

# _way_placed <config>
# Every module name inside the modules-left/center/right arrays, and inside
# any group's "modules" array, sorted. A group places its members itself, so
# they never appear in a modules-* array. Only a group/* block counts: the
# privacy module has a "modules" array too, of stream kinds ("audio-in"), not
# bar modules. `top` is the enclosing top-level key (two-space indent, as
# _way_configured reads it).
#
# Both array forms appear in this repo -- inline, as modules-left is written,
# and one-per-line, as modules-right is -- so the extractor tracks the array
# rather than matching a line shape. The key is stripped from the opening line
# before names are pulled out, so "modules-left" is not itself reported; a
# continuation line has no colon, so the strip is a no-op there.
#
# The // strip is what keeps a commented-out entry from being read as data, and
# it is safe HERE in a way a global strip would not be: inside a modules array
# every element is a bare module name, and no module name contains //. The
# module header's objection — that stripping // corrupts any string containing
# it — is about the file as a whole, where handler values are shell command
# lines that really can hold a URL. Nothing in this window can.
#
# Both symptoms this prevents are real, not hypothetical:
#   `// "custom/weather",` inside an array otherwise reports a module that is
#   not placed, and since it is a custom/* that is an ERROR — doctor.sh exiting
#   1 on a working bar, the failure references.sh argues against at length.
#   A `]` inside a comment (`// pinned, see notes[1]`) otherwise closes the
#   array early, dropping every module below it and re-reporting each of their
#   blocks as a false orphan. Testing `line` rather than `$0` is what fixes it,
#   so the comment strip has to happen before the bracket test, not after.
_way_placed() {
    awk '
        /^  "[^"]*"[[:space:]]*:/ { top = $0; sub(/^  "/, "", top); sub(/".*$/, "", top) }
        /^[[:space:]]*"modules-(left|center|right)"[[:space:]]*:/ { inarr = 1 }
        /^[[:space:]]*"modules"[[:space:]]*:/ && top ~ /^group\// { inarr = 1 }
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
    ' "$1" | sort -u
}

# _way_configured <config>
# Every module config block, i.e. every top-level key whose value opens a brace.
#
# The two-space indent excludes nested keys such as "actions" and "format".
# Requiring { excludes the scalar settings ("layer": "bottom") and the
# modules-* arrays themselves, which open [.
_way_configured() {
    sed -n 's/^  "\([^"]*\)"[[:space:]]*:[[:space:]]*{.*$/\1/p' "$1" | sort -u
}

# _way_commands <config>
# The first token of every handler value waybar executes as a shell command.
#
# The key list is upstream waybar vocabulary, the same kind of hardcoding as
# DOCTOR_WAYBAR_ACTIONS above and stale only on a waybar release. It is the
# subset this repo actually uses. KNOWINGLY OMITTED, all of which waybar also
# executes and none of which appears in the live config: exec-if,
# on-click-forward, on-click-backward, on-update. Adding one to config.jsonc
# without adding it here costs a missed WARN, never a false one — so the list
# fails safe, which is why it is worth keeping narrow rather than speculative.
_way_commands() {
    sed -n 's/^[[:space:]]*"\(exec\|on-click\|on-click-right\|on-click-middle\|on-scroll-up\|on-scroll-down\)"[[:space:]]*:[[:space:]]*"\([^"]*\)".*$/\2/p' "$1" \
        | awk 'NF { print $1 }' \
        | sort -u
}

# _way_have_cmd <token> — host probe, in its own function so tests can stub it.
#
# Handles an absolute path too, and better than a hand-rolled [ -x ] branch:
# `command -v /usr/bin` is false where `[ -x /usr/bin ]` is true, so a handler
# pointing at a directory is caught rather than passed. Routing absolute paths
# through here also keeps them inside the one seam the tests stub.
_way_have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# _way_is_action <token> — true for one of waybar's own action keywords.
_way_is_action() {
    case "$DOCTOR_WAYBAR_ACTIONS" in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

check_waybar() {
    group "Waybar"

    local config="$DOCTOR_ROOT/waybar/config.jsonc"
    local before_errors="$DOCTOR_ERRORS"
    local before_warnings="$DOCTOR_WARNINGS"
    local before_notices="$DOCTOR_NOTICES"
    local placed configured name cmd

    if [ ! -f "$config" ]; then
        note "no waybar/config.jsonc in $DOCTOR_ROOT — nothing to check" \
             "restore $(doctor_q "$config") if this clone is meant to have a bar"
        return 0
    fi

    placed="$(_way_placed "$config")"
    configured="$(_way_configured "$config")"

    # Process substitution, not a pipeline — see the contract note in lib.sh.
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        printf '%s\n' "$configured" | grep -qxF -- "$name" && continue

        case "$name" in
            custom/*)
                err "waybar places $name, which has no config block — a custom module without one has nothing to run" \
                    "add a \"$name\" block to $(doctor_q "$config"), or drop the name from the modules list"
                ;;
            *)
                warn "waybar places $name, which has no config block — it renders on waybar defaults, or the name is a typo waybar will drop" \
                     "add a \"$name\" block to $(doctor_q "$config"), or correct the name in the modules list"
                ;;
        esac
    done < <(printf '%s\n' "$placed")

    while IFS= read -r name; do
        [ -n "$name" ] || continue
        printf '%s\n' "$placed" | grep -qxF -- "$name" && continue
        note "waybar configures $name but places it in no modules list" \
             "add $name to a modules- list in $(doctor_q "$config"), or delete the block"
    done < <(printf '%s\n' "$configured")

    while IFS= read -r cmd; do
        [ -n "$cmd" ] || continue

        # references.sh owns every ~/.config path in a tracked file, and this
        # file is tracked. Both spellings, as configs write them.
        # shellcheck disable=SC2088
        case "$cmd" in
            '~/.config/'*|'$HOME/.config/'*) continue ;;
        esac

        _way_is_action "$cmd" && continue
        _way_have_cmd "$cmd" && continue

        warn "waybar invokes $cmd, which is not installed" \
             "install the package providing $cmd, or change the handler in $(doctor_q "$config")"
    done < <(_way_commands "$config")

    # ok is the all-clear and nothing else — see the note in references.sh.
    if [ "$DOCTOR_ERRORS" -eq "$before_errors" ] &&
       [ "$DOCTOR_WARNINGS" -eq "$before_warnings" ] &&
       [ "$DOCTOR_NOTICES" -eq "$before_notices" ]; then
        ok "every waybar module is configured and every handler resolves"
    fi
}
