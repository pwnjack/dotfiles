#!/bin/bash
#
# The machine-state overlay (scripts/state/overlay.sh): every file under
# defaults/ has a rendered live copy at the same path, which git ignores and
# never tracks. Targets come from defaults/ itself; nothing is listed here.
# Dot-files under defaults/ are not targets, as in overlay-cli.mjs.

DOCTOR_STATE_DIR="${DOCTOR_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles}"

# _st_live_paths -> every live path the overlay renders, NUL-separated.
_st_live_paths() {
    local defaults="$DOCTOR_ROOT/defaults"
    [ -d "$defaults" ] || return 0
    find "$defaults" -type f ! -name '.*' -printf '%P\0'
}

_st_tracked() { git -C "$DOCTOR_ROOT" ls-files --error-unmatch -- "$1" >/dev/null 2>&1; }
_st_ignored() { git -C "$DOCTOR_ROOT" check-ignore -q -- "$1"; }
# A defaults/ file must be tracked, so an ignore rule matching it is a mistake
# (--no-index: judge the rule, not whether the file happens to be tracked).
_st_default_ignored() { git -C "$DOCTOR_ROOT" check-ignore -q --no-index -- "defaults/$1"; }
_st_overrides_report() { node "$DOCTOR_ROOT/scripts/state/overlay-cli.mjs" check "$DOCTOR_ROOT" "$DOCTOR_STATE_DIR" 2>&1; }
_st_have_node() { command -v node >/dev/null 2>&1; }

check_state() {
    group "Machine state"
    local before=$((DOCTOR_ERRORS + DOCTOR_WARNINGS)) path line hint
    hint="bash $(doctor_q "$DOCTOR_ROOT/scripts/state/overlay.sh") sync"
    while IFS= read -r -d '' path; do
        if _st_default_ignored "$path"; then
            err "defaults/$path matches an ignore rule, so git would never track it" "anchor the rule in $(doctor_q "$DOCTOR_ROOT/.gitignore")"
        fi
        if [ ! -e "$DOCTOR_ROOT/$path" ]; then
            err "$path has not been rendered" "$hint"
        elif _st_tracked "$path"; then
            err "$path is tracked, but the overlay renders it" "git -C $(doctor_q "$DOCTOR_ROOT") rm --cached -- $(doctor_q "$path")"
        elif ! _st_ignored "$path"; then
            err "$path is not ignored by .gitignore" "add it to the overlay block in $(doctor_q "$DOCTOR_ROOT/.gitignore")"
        fi
    done < <(_st_live_paths)
    if _st_have_node && [ -f "$DOCTOR_ROOT/scripts/state/overlay-cli.mjs" ]; then
        while IFS= read -r line; do
            [ -n "$line" ] && warn "Overrides file does not parse: $line" "fix or delete it under $(doctor_q "$DOCTOR_STATE_DIR/overrides")"
        done < <(_st_overrides_report)
    fi
    if [ -n "${XDG_STATE_HOME:-}" ] && [ "$XDG_STATE_HOME" != "$HOME/.local/state" ]; then
        warn "XDG_STATE_HOME is $XDG_STATE_HOME, but hypridle.conf sources ~/.local/state/hypr/hypridle.conf" "unset XDG_STATE_HOME, or link the two directories"
    fi
    if [ $((DOCTOR_ERRORS + DOCTOR_WARNINGS)) -eq "$before" ]; then ok "Machine state renders are in place"; fi
}
