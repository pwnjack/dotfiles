#!/bin/bash
#
# The update card's plan: pending repo and AUR updates, how much needs
# downloading, and whether the running kernel is replaced. No root.
#
# checkupdates syncs a private copy of the sync DBs; `pacman -Sup --dbpath`
# against that copy then lists every package the upgrade would fetch,
# including new dependencies (measured: works unprivileged). A package whose
# file is already in the cache downloads nothing and counts as 0.
#
# Exit status: 0 with the plan on stdout. Otherwise one reason line on stderr,
# no JSON, and:
#   1  checkupdates missing, failed (any status but 0 or 2), or its lock timed
#      out
#   3  `pacman -Sup` cannot resolve the upgrade, so it needs a terminal
# The card shows any failure as an error instead of a false "Up to date"; the
# bar (scripts/waybar/updates.sh) hides on 1 and shows an attention glyph on 3.
# The AUR helper's status stays ignored: `paru -Qua` exits unreliably, and the
# AUR list is derived from options/aurhelper. Flatpak's status is ignored too:
# its count is the lines `remote-ls --updates` prints, 0 on any failure.
#
# checkupdates runs under `flock -w` on "$DB.lock" (LOCK below), because the
# private sync DB is shared between the card and the bar, which both run
# this script.
#
# Every plan printed is also saved as $XDG_RUNTIME_DIR/updates/plan.json, so
# the card can open on the last check instead of repeating it. `checkedAt` is
# when the check began. A check that finds the upgrade unresolvable (exit 3)
# removes the saved plan; one that cannot run (exit 1) leaves it.
#
# `updates-plan.sh --cached` prints that saved plan and exits 0, or exits 4
# when there is none, or when pacman's local database or a Flatpak
# installation changed after the check began (an update ran, from the card, a
# terminal or anywhere else). It never checks the network; how old a plan may
# be is the caller's decision.
#
# Test seams: UPDATES_REPO_CMD, UPDATES_AURHELPER, UPDATES_AUR_CMD,
# UPDATES_CACHE_DIR, UPDATES_KERNEL, UPDATES_MODULES_DIR, UPDATES_DB,
# UPDATES_LOCK_TIMEOUT, UPDATES_FLATPAK, UPDATES_STATE_DIR, UPDATES_LOCAL_DB.
#
set -uo pipefail

STATE_DIR="${UPDATES_STATE_DIR:-${XDG_RUNTIME_DIR:-/run/user/$UID}/updates}"
SAVED="$STATE_DIR/plan.json"
FLATPAK="${UPDATES_FLATPAK:-flatpak}"

if [ "${1-}" = --cached ]; then
    # Installing or removing a package adds or removes an entry in local/,
    # which moves the directory's mtime.
    local_db="${UPDATES_LOCAL_DB-}"
    if [ -z "$local_db" ]; then
        local_db=$(pacman-conf DBPath 2>/dev/null | head -n1)
        local_db="${local_db:-/var/lib/pacman/}"
        local_db="${local_db%/}/local"
    fi
    checked=$(jq -er '.checkedAt | numbers' "$SAVED" 2>/dev/null) || exit 4
    changed=$(stat -c %Y -- "$local_db" 2>/dev/null) || exit 4
    [ "$changed" -lt "$checked" ] || exit 4
    # Flatpak touches <installation>/.changed on every deploy and uninstall.
    markers=("${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/.changed")
    if command -v "$FLATPAK" >/dev/null 2>&1; then
        while IFS= read -r dir; do
            [ -n "$dir" ] && markers+=("$dir/.changed")
        done < <("$FLATPAK" --installations 2>/dev/null)
    fi
    for marker in "${markers[@]}"; do
        [ -e "$marker" ] || continue
        changed=$(stat -c %Y -- "$marker" 2>/dev/null) || exit 4
        [ "$changed" -lt "$checked" ] || exit 4
    done
    cat -- "$SAVED"
    exit 0
fi
checked_at=$(date +%s)

REPO_CMD="${UPDATES_REPO_CMD:-checkupdates}"
KERNEL="${UPDATES_KERNEL:-$(uname -r)}"
MODULES="${UPDATES_MODULES_DIR:-/usr/lib/modules}"
DB="${UPDATES_DB:-${TMPDIR:-/tmp}/checkup-db-${UID}}"
AURHELPER_FILE="${UPDATES_AURHELPER-}"
[ -n "$AURHELPER_FILE" ] || AURHELPER_FILE="$HOME/.config/options/aurhelper"
CACHE="${UPDATES_CACHE_DIR-}"
[ -n "$CACHE" ] || CACHE=$(pacman-conf CacheDir 2>/dev/null | head -n1)
CACHE="${CACHE%/}"
LOCK="$DB.lock"
LOCK_TIMEOUT="${UPDATES_LOCK_TIMEOUT:-120}"

fail() { echo "$1" >&2; exit "${2:-1}"; }

command -v "$REPO_CMD" >/dev/null 2>&1 || fail "Could not check for updates (checkupdates is not installed)"
repo=$(CHECKUPDATES_DB="$DB" flock -w "$LOCK_TIMEOUT" -E 200 "$LOCK" "$REPO_CMD" 2>/dev/null)
case $? in
    0|2) ;;
    200) fail "Could not check for updates (another check is still running)" ;;
    *) fail "Could not sync package databases (offline?)" ;;
esac

sizes=""
if [ -n "$repo" ]; then
    plist=$(LC_ALL=C pacman -Sup --dbpath "$DB" --print-format '%n %s %l' 2>/dev/null) ||
        { rm -f -- "$SAVED"; fail "pacman cannot resolve this upgrade; update in a terminal" 3; }
    while read -r name size location; do
        [ -n "$name" ] || continue
        [[ "$size" =~ ^[0-9]+$ ]] || continue
        [ -n "$CACHE" ] && [ -e "$CACHE/${location##*/}" ] && size=0
        sizes+="$name $size"$'\n'
    done <<< "$plist"
fi

owners=""
[ -n "$repo" ] && owners=$(pacman -Qqo "$MODULES/$KERNEL" 2>/dev/null)

aur_cmd="${UPDATES_AUR_CMD-}"
if [ -z "${UPDATES_AUR_CMD+set}" ]; then
    aur_cmd=$(awk 'NR==1 {print $1}' "$AURHELPER_FILE" 2>/dev/null)
fi
aur=""
if [ -n "$aur_cmd" ] && command -v "$aur_cmd" >/dev/null 2>&1; then
    aur=$("$aur_cmd" -Qua 2>/dev/null)
fi

# Flatpak: only when something is installed -- the same guard updates-run.sh
# uses before its Flatpak phase. Runtimes count too; the run updates them.
flatpak=0
if command -v "$FLATPAK" >/dev/null 2>&1 \
    && [ -n "$("$FLATPAK" list --columns=application 2>/dev/null | head -n1)" ]; then
    flatpak=$("$FLATPAK" remote-ls --updates --columns=application 2>/dev/null | grep -c .)
fi

plan=$(jq -nc --arg repo "$repo" --arg sizes "$sizes" --arg owners "$owners" --arg aur "$aur" \
    --argjson flatpak "$flatpak" --argjson checked "$checked_at" '
    def rows($text): $text | split("\n") | map(select(length > 0));
    def updates($text): [rows($text)[] | capture("^(?<name>\\S+) (?<old>\\S+) -> (?<new>\\S+)")?];
    (rows($sizes) | map(split(" ") | {key: .[0], value: (.[1] | tonumber)}) | from_entries) as $size
    | rows($owners) as $kernel
    | (updates($repo) | map(. + {bytes: ($size[.name] // 0), kernel: (.name as $n | $kernel | index([$n]) != null)})) as $rows
    | {repo: $rows, aur: updates($aur), bytes: ([$size[]] | add // 0), kernel: ($rows | any(.kernel)), flatpak: $flatpak,
       checkedAt: $checked}') || fail "Could not build the update plan"
printf '%s\n' "$plan"

# Saving is best effort: the plan on stdout stands even if the copy fails.
if mkdir -p -- "$STATE_DIR" 2>/dev/null && tmp=$(mktemp "$SAVED.XXXXXX" 2>/dev/null); then
    if ! { printf '%s\n' "$plan" > "$tmp" && mv -f -- "$tmp" "$SAVED"; }; then rm -f -- "$tmp"; fi
fi
