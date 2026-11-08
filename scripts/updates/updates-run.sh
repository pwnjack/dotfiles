#!/bin/bash
#
# One background system update, published as state for the card and the bar.
#
# The update card starts this under `setsid -f`, so closing the card or
# restarting Waybar never stops an update. Output:
#   $XDG_RUNTIME_DIR/updates/run.log     the raw stream (pacman + @@ markers)
#   $XDG_RUNTIME_DIR/updates/state.json  folded by fold.mjs (model.mjs)
#
# Root is only the helper's: `sudo -n /usr/local/bin/system-update`, allowed
# without a password by updates/setup-sudo.sh. Flatpak runs here, as the user,
# after pacman succeeds (polkit lets an active session update apps).
#
# Restart detection is derived, not listed: replacing the running kernel
# removes /usr/lib/modules/$(uname -r), so its absence after a successful run
# is the signal; nothing here knows package names.
#
# The run never depends on the fold surviving: `tee -p` keeps run.log and the
# helper's stdout alive if fold.mjs dies, and afterwards a dead or unfinished
# fold is redone from the complete run.log, then replaced by a minimal terminal
# snapshot, so state.json is never left saying "running".
#
# Test seams: UPDATES_STATE_DIR, UPDATES_HELPER, UPDATES_SUDO=none,
# UPDATES_MODULES_DIR, UPDATES_KERNEL, UPDATES_FLATPAK, UPDATES_FLATPAK_TIMEOUT,
# UPDATES_FOLD (a command replacing node fold.mjs), UPDATES_SIGNAL=none.
#
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
state_dir="${UPDATES_STATE_DIR:-${XDG_RUNTIME_DIR:-/run/user/$UID}/updates}"
helper="${UPDATES_HELPER:-/usr/local/bin/system-update}"
modules="${UPDATES_MODULES_DIR:-/usr/lib/modules}"
kernel="${UPDATES_KERNEL:-$(uname -r)}"
flatpak="${UPDATES_FLATPAK:-flatpak}"
flatpak_timeout="${UPDATES_FLATPAK_TIMEOUT:-20m}"
if [ -n "${UPDATES_FOLD-}" ]; then fold=("$UPDATES_FOLD"); else fold=(node "$here/fold.mjs"); fi
if [ "${UPDATES_SUDO-}" = none ]; then priv=(); else priv=(sudo -n); fi

mkdir -p "$state_dir" || exit 1
exec 8>"$state_dir/run.lock"
flock -n 8 || exit 75

# Nothing from the previous run may outlive the lock being taken: a card
# polling state.json would otherwise show the old result for the new run.
rm -f "$state_dir/ack" "$state_dir/state.json"
: > "$state_dir/run.log"
started=$(date +%s)

# newest_modules — the module directory of the newest kernel of the running
# kernel's flavour (the part after pkgrel: -cachyos vs -cachyos-lts), else the
# most recently modified directory.
newest_modules() {
    local dir name best='' flavour=''
    if [[ $kernel =~ ^[0-9.]+-[0-9]+(-.+)$ ]]; then flavour="${BASH_REMATCH[1]}"; fi
    if [ -n "$flavour" ]; then
        for dir in "$modules"/*/; do
            name=$(basename "$dir")
            [[ $name =~ ^[0-9.]+-[0-9]+${flavour}$ ]] && printf '%s\n' "$name"
        done | sort -V | tail -n1 | { read -r best; printf '%s' "$best"; }
        return
    fi
}

# snapshot_fallback — a terminal state.json written without the model, for when
# every fold failed. Same fields as model.snapshot().
snapshot_fallback() {
    printf '{"status":"attention","phase":"sync","key":"sync","line":"","progress":0,"done":0,"total":0,"bytes":0,"totalBytes":0,"error":"The update ran, but its progress was not recorded","detail":"See run.log","errorKind":"unknown","restart":"","nothing":false,"startedAt":%s,"finishedAt":%s}\n' \
        "$started" "$(date +%s)" > "$state_dir/state.json.fallback" \
        && mv -f "$state_dir/state.json.fallback" "$state_dir/state.json"
}

{
    "${priv[@]}" "$helper" 8>&- </dev/null 2>&1
    status=$?
    echo "@@helper-exit $status"
    if [ "$status" -eq 0 ] && command -v "$flatpak" >/dev/null 2>&1 \
        && [ -n "$("$flatpak" list --columns=application 2>/dev/null | head -n1)" ]; then
        echo '@@phase flatpak'
        timeout "$flatpak_timeout" "$flatpak" update --noninteractive -y 8>&- </dev/null 2>&1
        echo "@@flatpak-exit $?"
    fi
    if [ "$status" -eq 0 ] && [ ! -d "$modules/$kernel" ]; then
        newest=$(newest_modules)
        if [ -z "$newest" ]; then
            # shellcheck disable=SC2012  # names are kernel versions, never odd characters
            newest=$(ls -1t "$modules" 2>/dev/null | head -n1)
        fi
        echo "@@restart ${newest:-unknown}"
    fi
    echo '@@end'
} | tee -p -a "$state_dir/run.log" | "${fold[@]}" "$state_dir/state.json" "$started" 8>&-
pipe=("${PIPESTATUS[@]}")

if [ "${pipe[2]}" -ne 0 ] || grep -q '"status":"running"' "$state_dir/state.json" 2>/dev/null \
    || [ ! -e "$state_dir/state.json" ]; then
    "${fold[@]}" "$state_dir/state.json" "$started" < "$state_dir/run.log" 8>&-
    if [ ! -e "$state_dir/state.json" ] || grep -q '"status":"running"' "$state_dir/state.json"; then
        snapshot_fallback
    fi
fi

# Release the lock BEFORE the last signal: fold.mjs signals Waybar on its final
# write while the lock is still held, and the bar reads a held lock as running.
exec 8>&-
if [ "${UPDATES_SIGNAL-}" != none ]; then
    pkill -x -RTMIN+9 waybar >/dev/null 2>&1 || true
fi
exit 0
