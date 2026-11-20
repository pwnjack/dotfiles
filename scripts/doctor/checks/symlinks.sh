#!/bin/bash
#
# Symlink integrity. The list of symlinks is derived from git itself:
# `git ls-files -s` reports mode 120000 for every tracked symlink, so no path
# is ever enumerated here and a newly committed symlink is covered the moment
# it lands. The index — not the working tree — is the source of truth for what
# *should* be a symlink, which is what lets this catch a link that some tool
# has overwritten with a regular file.
#
# The listing is read NUL-delimited (-z). Without it git renders a path holding
# a quote or a non-ASCII byte as a C-quoted string ("\303\274..."), which no
# longer names a file on disk and would be misreported as dangling.
#
# In this repo every symlink points into ~/.cache, so an absolute target is
# always a portability bug: it bakes one machine's home path into a tracked
# file. Any absolute target is therefore flagged, not just /home/*.
#
# DOCTOR_ROOT is assumed to be a git work tree; doctor.sh establishes that once
# via doctor_require_repo, so an empty listing here means "no symlinks", not
# "no repository".
#
# Accepted limitations:
#   - A symlink whose *target* contains a newline splits its report line in
#     two. lib.sh prints messages literally by design (paths and regexes must
#     survive verbatim), and no such target exists in practice.
#   - A link under an unreadable parent directory fails the -L test and is
#     reported as missing from the working tree, with a checkout hint that will
#     not help. Telling EACCES from ENOENT needs stat(2), and a dotfiles tree
#     the user cannot traverse has a larger problem than this check.
#

check_symlinks() {
    group "Symlinks"

    local total=0 before
    local record mode path full target relative
    before=$(doctor_findings)

    while IFS= read -r -d '' record; do
        mode="${record%% *}"
        [ "$mode" = "120000" ] || continue
        # Everything past the first tab is the path, verbatim.
        path="${record#*$'\t'}"
        total=$((total + 1))
        full="$DOCTOR_ROOT/$path"

        if [ ! -L "$full" ]; then
            if [ -e "$full" ]; then
                # Back the file up first: checkout discards its contents, and
                # whatever wrote it may hold the only copy. Re-running that
                # writer is not the fix — it is what clobbered the link.
                err "$path is a regular file, but git tracks it as a symlink" \
                    "cp -a $(doctor_q "$full") $(doctor_q "$full.bak") && git -C $(doctor_q "$DOCTOR_ROOT") checkout -- $(doctor_q "$path")"
            else
                err "$path is tracked as a symlink but missing from the working tree" \
                    "git -C $(doctor_q "$DOCTOR_ROOT") checkout -- $(doctor_q "$path")"
            fi
            continue
        fi

        target="$(readlink "$full")"

        # -e cannot tell a missing target from a symlink loop (ENOENT vs
        # ELOOP), so the wording has to cover both.
        if [ ! -e "$full" ]; then
            err "$path → $target (does not resolve)" \
                "recreate the target, or repoint it: ln -sfn NEW_TARGET $(doctor_q "$full")"
        elif [[ "$target" == /* ]]; then
            # Suggest the equivalent relative target so the fix is copy-pasteable.
            relative="$(realpath -ms --relative-to="${full%/*}" "$target" 2>/dev/null)"
            warn "$path → $target (absolute target is not portable)" \
                 "ln -sfn $(doctor_q "${relative:-NEW_TARGET}") $(doctor_q "$full")"
        fi
    done < <(git -C "$DOCTOR_ROOT" ls-files -sz 2>/dev/null)

    if [ "$total" -eq 0 ]; then
        note "no tracked symlinks found — nothing to check"
    else
        ok_if_clean "$before" "all $total tracked symlinks are healthy and portable"
    fi
}
