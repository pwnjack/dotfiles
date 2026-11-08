#!/bin/bash
#
# Build the native Waybar workspace module (waybar/workspaces) and render the
# include that tells Waybar where it is.
#
# Waybar hands module_path to dlopen verbatim -- no ~ expansion -- so the
# tracked config.jsonc cannot name the library on every machine. The rendered
# include carries the absolute path, and Waybar merges it into config.jsonc's
# cffi/workspaces block key by key. "source" is informational only (where the
# library was built from); doctor.sh hashes its own checkout's sources through
# --check, and the module ignores both keys.
#
# Rebuilds only when the installed library's content stamp (a sha256 over the
# Makefile, the C sources and headers, and this script, beside the library as
# <lib>.sha256) is missing or differs, so install.sh and doctor.sh's fix hint
# can both run it blindly. Deleted sources, older mtimes and another
# worktree's build all change the stamp. `--check` compares only: it builds and
# writes nothing, and exits 0 when the library is current, 1 when missing or
# stale. The build runs in a temporary directory (the repository never holds
# build output), and the library is renamed into place: a running Waybar keeps
# its mapping of the old file instead of executing a half-written one.
set -euo pipefail

check=0
case "${1:-}" in
    '') ;;
    --check) check=1 ;;
    *) echo "usage: build-workspaces.sh [--check]" >&2; exit 2 ;;
esac

self="${BASH_SOURCE[0]}"
repo="$(cd "$(dirname "$self")/../.." && pwd)"
src="${WORKSPACES_SRC:-$repo/waybar/workspaces}"
lib="${WORKSPACES_LIB:-$HOME/.local/lib/waybar/workspaces.so}"
include="${WORKSPACES_INCLUDE:-$HOME/.local/state/waybar/workspaces.jsonc}"

for var in WORKSPACES_SRC WORKSPACES_LIB WORKSPACES_INCLUDE; do
    if [ -n "${!var:-}" ] && [ "${!var#/}" = "${!var}" ]; then
        echo "build-workspaces: $var must be an absolute path" >&2
        exit 1
    fi
done
if [ ! -f "$src/Makefile" ]; then
    echo "build-workspaces: $src/Makefile not found" >&2
    exit 1
fi

# Names and contents, so a rename or deletion changes the stamp too.
source_stamp() {
    {
        while IFS= read -r -d '' f; do
            printf '%s\0' "${f##*/}"
            cat "$f"
        done < <(find "$src" -maxdepth 1 -type f \( -name '*.c' -o -name '*.h' -o -name Makefile \) \
            -print0 | LC_ALL=C sort -z)
        cat "$self"
    } | sha256sum | cut -d' ' -f1
}

if ! command -v sha256sum >/dev/null 2>&1; then
    echo "build-workspaces: sha256sum is not installed" >&2
    exit 1
fi

# One install at a time per library: the library and its stamp are renamed in
# two steps, and two runs from different checkouts must not pair one's library
# with the other's stamp. --check writes nothing, so it takes no lock.
if [ "$check" != 1 ]; then
    if ! command -v flock >/dev/null 2>&1; then
        echo "build-workspaces: flock is not installed" >&2
        exit 1
    fi
    mkdir -p "${lib%/*}"
    exec 9>"$lib.lock"
    flock 9
fi

want="$(source_stamp)"
have=''
[ ! -f "$lib.sha256" ] || have="$(cat "$lib.sha256")"

if [ ! -f "$lib" ]; then
    stale_reason='missing'
elif [ "$have" != "$want" ]; then
    stale_reason='stale'
else
    stale_reason=''
fi

if [ "$check" = 1 ]; then
    if [ -n "$stale_reason" ]; then
        echo "build-workspaces: $lib is $stale_reason"
        exit 1
    fi
    exit 0
fi

for tool in make cc pkg-config jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "build-workspaces: $tool is not installed" >&2
        exit 1
    fi
done
if ! pkg-config --exists gtk+-3.0 json-glib-1.0; then
    echo "build-workspaces: the gtk3 and json-glib development files are missing" >&2
    exit 1
fi

build=''
tmp_lib=''
tmp_stamp=''
tmp_include=''
cleanup() {
    [ -z "$build" ] || rm -rf "$build"
    rm -f "$tmp_lib" "$tmp_stamp" "$tmp_include"
}
trap cleanup EXIT

if [ -n "$stale_reason" ]; then
    build="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/workspaces-build.XXXXXX")"
    make -s -C "$src" BUILD="$build" WS_WERROR= "$build/workspaces.so"
    mkdir -p "${lib%/*}"
    tmp_lib="$(mktemp "$lib.XXXXXX")"
    cp "$build/workspaces.so" "$tmp_lib"
    chmod 0755 "$tmp_lib" # mktemp creates 0600
    mv -f "$tmp_lib" "$lib"
    tmp_lib=''
    tmp_stamp="$(mktemp "$lib.sha256.XXXXXX")"
    printf '%s\n' "$want" > "$tmp_stamp"
    chmod 0644 "$tmp_stamp"
    mv -f "$tmp_stamp" "$lib.sha256"
    tmp_stamp=''
    echo "build-workspaces: installed $lib; restart Waybar to load it"
fi

mkdir -p "${include%/*}"
tmp_include="$(mktemp "$include.XXXXXX")"
jq -n --arg path "$lib" --arg source "$src" \
    '{"cffi/workspaces": {"module_path": $path, "source": $source}}' > "$tmp_include"
chmod 0644 "$tmp_include"
if cmp -s "$tmp_include" "$include"; then
    rm -f "$tmp_include"
else
    mv -f "$tmp_include" "$include"
fi
tmp_include=''
