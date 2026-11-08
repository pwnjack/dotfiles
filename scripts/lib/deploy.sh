#!/bin/bash
# Shared deployment plan: the tracked working-tree files are both the copy list
# and the backup list. Source this file; nothing happens until deploy_dotfiles.

_deploy_run() {
    local dry=$1
    shift
    if [ "$dry" = true ]; then
        printf '[DRY RUN]'; printf ' %q' "$@"; printf '\n'
    else
        "$@"
    fi
}

# Refuse directory symlinks and file/directory conflicts before any writes.
# A leaf symlink is safe: cp --remove-destination replaces the link itself.
_deploy_parent_ok() {
    local root=$1 path=$2 parent
    parent=$(dirname "$path")
    while [ "$parent" != . ]; do
        if [ -L "$root/$parent" ] || { [ -e "$root/$parent" ] && [ ! -d "$root/$parent" ]; }; then
            printf 'deploy: parent is not a regular directory: %s\n' "$root/$parent" >&2
            return 1
        fi
        parent=$(dirname "$parent")
    done
}

deploy_dotfiles() {
    local source=$1 destination=$2 backup=$3 dry=$4 no_backup=$5
    local manifest path
    local -a files=()
    manifest=$(mktemp) || return 1
    if ! git -C "$source" ls-files -z > "$manifest"; then
        rm -f "$manifest"
        echo 'deploy: a Git checkout is required to identify deployable files' >&2
        return 1
    fi
    while IFS= read -r -d '' path; do
        case "$path" in
            .github|.github/*) continue ;;
        esac
        files+=("$path")
    done < "$manifest"
    rm -f "$manifest"
    [ "${#files[@]}" -gt 0 ] || { echo 'deploy: no tracked files found' >&2; return 1; }
    if [ -L "$destination" ] || { [ -e "$destination" ] && [ ! -d "$destination" ]; }; then
        echo 'deploy: destination must be a regular directory' >&2
        return 1
    fi
    if [ "$no_backup" = false ] && { [ -e "$backup" ] || [ -L "$backup" ]; }; then
        echo 'deploy: backup path already exists; refusing to overwrite it' >&2
        return 1
    fi
    for path in "${files[@]}"; do
        _deploy_parent_ok "$source" "$path" || return 1
        _deploy_parent_ok "$destination" "$path" || return 1
        if { [ ! -f "$source/$path" ] && [ ! -L "$source/$path" ]; } \
            || { [ -d "$destination/$path" ] && [ ! -L "$destination/$path" ]; }; then
            printf 'deploy: missing source or destination directory conflict: %s\n' "$path" >&2
            return 1
        fi
    done
    # Complete all backups before overwriting the first destination.
    if [ "$no_backup" = false ]; then
        _deploy_run "$dry" mkdir -p -- "$backup" || return 1
        for path in "${files[@]}"; do
            if [ -e "$destination/$path" ] || [ -L "$destination/$path" ]; then
                _deploy_run "$dry" mkdir -p -- "$backup/$(dirname "$path")" || return 1
                _deploy_run "$dry" cp -aT -- "$destination/$path" "$backup/$path" || return 1
            fi
        done
    fi
    for path in "${files[@]}"; do
        _deploy_run "$dry" mkdir -p -- "$destination/$(dirname "$path")" || return 1
        _deploy_run "$dry" cp -aT --remove-destination -- "$source/$path" "$destination/$path" || return 1
    done
}
