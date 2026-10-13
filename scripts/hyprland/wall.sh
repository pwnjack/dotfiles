#!/bin/bash
# Serialize wallpaper changes, reading the current selection after taking the
# lock so queued requests cannot restore an older palette. The new palette is
# published part-way through the wallpaper transition, not before it shows.
set -uo pipefail

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"

# shellcheck source=scripts/lib/wallpaper.sh
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/../lib/wallpaper.sh"

notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -i preferences-desktop-wallpaper "$1" "$2" 9>&- || true
}
fail() {
    echo "wallpaper: $*" >&2
    notify "Wallpaper theme failed" "$*"
    exit 1
}

now_ns() { date +%s%N; }

# publish_delay_ns -> how long after the wallpaper transition starts to publish
# the new palette, in nanoseconds: 60% of the duration Waypaper asked awww for,
# so the recolour lands while the new image is coming in and the ~0.1 s of
# component updates ends with the transition rather than after it. 0 when
# Waypaper is not driving awww (or swww), or the transition is instant or
# step-driven ('simple' ignores the duration and, at Waypaper's step, finishes
# in a few frames). 'any' and 'random' may pick 'simple'; the duration stays
# their bound. awww img returns as the transition starts, so wall.sh begins
# with it.
publish_delay_ns() {
    local ini="$config_dir/waypaper/config.ini" backend type duration
    backend=$(sed -n 's/^backend *= *//p' "$ini" 2>/dev/null | head -n1)
    type=$(sed -n 's/^swww_transition_type *= *//p' "$ini" 2>/dev/null | head -n1)
    duration=$(sed -n 's/^swww_transition_duration *= *//p' "$ini" 2>/dev/null | head -n1)
    case "$backend" in awww|swww) ;; *) echo 0; return ;; esac
    case "$type" in none|simple) echo 0; return ;; esac
    [[ "$duration" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo 0; return; }
    LC_ALL=C awk -v d="$duration" 'BEGIN { d = d > 10 ? 10 : d; printf "%d\n", d * 0.6 * 1e9 }'
}

# saved_ns -> when Waypaper last saved its selection, in nanoseconds since the
# epoch (0 when unknown). It saves just after starting the transition, so this
# dates the newest change even when this run waited in the queue behind others.
saved_ns() {
    local stamp
    stamp=$(LC_ALL=C stat -L -c %.9Y "$config_dir/waypaper/config.ini" 2>/dev/null) || { echo 0; return; }
    echo "${stamp//[^0-9]/}"
}

started=$(now_ns)

command -v flock >/dev/null 2>&1 || fail "flock is not installed"
mkdir -p "$cache_dir/wal" || fail "Cannot create the palette cache"
exec 9>"$cache_dir/wal/wallpaper.lock"
queued=0
flock -n 9 || { queued=1; flock 9; } || fail "Cannot lock the wallpaper pipeline"

# The palette is generated into a staging cache while awww's transition plays
# and published part-way through it (publish_delay_ns), so colours change with
# the new wallpaper instead of before it is visible. pywal writes every template into its
# cache, and consumers watch those files (Waybar restyles on change), so
# generating in place would publish immediately. Scheme caching is shared with
# the real cache through a symlink.
stage="$cache_dir/wal/next"
mkdir -p "$stage" "$cache_dir/wal/schemes" || fail "Cannot create the palette staging cache"
[ -e "$stage/schemes" ] || ln -sfn ../schemes "$stage/schemes" || fail "Cannot share the palette scheme cache"
delay=$(publish_delay_ns)

# changed_after: the selection we stage cannot have changed before this
# moment. It starts at this run's own start and moves to each query that
# showed a since-replaced wallpaper. A few rounds bound a run under a fast
# slideshow; after them the newest selection is published without waiting.
changed_after=$started
for round in 1 2 3 4; do
    queried=$(now_ns)
    # Children must not keep our lock alive (several renderers start daemons).
    query=$(awww query 9>&-) || fail "Cannot read the current wallpaper"
    wallpaper=$(wallpaper_from_query "$query")
    [ -f "$wallpaper" ] || fail "The selected wallpaper is unavailable"

    # wal is synchronous. Do not publish new wallpaper state or reload
    # consumers when generation failed; no fixed sleep can turn that failure
    # into success. awww already owns the wallpaper. Keep pywal's
    # diagnostics: -q suppresses even Python tracebacks, making a failed
    # template impossible to identify.
    if ! PYWAL_CACHE_DIR="$stage" wal -n -s -t -e -i "$wallpaper" 9>&- \
            > "$cache_dir/wal/generation.log" 2>&1; then
        cat "$cache_dir/wal/generation.log" >&2
        fail "Could not generate colors from $(basename "$wallpaper")"
    fi

    since=$(saved_ns)
    [ "$since" -gt "$changed_after" ] || since=$changed_after
    remaining=$(( since + delay - $(now_ns) ))
    [ "$round" -lt 4 ] && [ "$remaining" -gt 0 ] || break
    sleep "$(LC_ALL=C awk -v n="$remaining" 'BEGIN { printf "%.3f\n", n / 1e9 }')" 9>&-

    query=$(awww query 9>&-) || fail "Cannot read the current wallpaper"
    [ "$(wallpaper_from_query "$query")" != "$wallpaper" ] || break
    changed_after=$queried
done

# A run that waited behind another usually finds that one already published
# the newest wallpaper; publishing it again would only repeat every reload and
# notification. A run that did not wait still publishes, so selecting the same
# wallpaper again re-applies it.
if [ "$queued" -eq 1 ] && [ "$cache_dir/current_wallpaper" -ef "$wallpaper" ] \
        && cmp -s "$stage/colors.json" "$cache_dir/wal/colors.json"; then
    exit 0
fi

# Publish: render every template into the real cache and recolour terminals
# from the staged scheme (pywal's own reloads included), as a direct run would.
if ! wal -n --theme "$stage/colors.json" 9>&- >> "$cache_dir/wal/generation.log" 2>&1; then
    cat "$cache_dir/wal/generation.log" >&2
    fail "Could not apply the colors from $(basename "$wallpaper")"
fi
cp -f "$stage/wal" "$cache_dir/wal/wal" 2>/dev/null || true
ln -sfn "$wallpaper" "$cache_dir/current_wallpaper" || fail "Cannot save the current wallpaper"
escaped=${wallpaper//\\/\\\\}
escaped=${escaped//\"/\\\"}
printf '* { wallpaper: url("%s", width); }\n' "$escaped" > "$cache_dir/wal/rofi-wallpaper.rasi" \
    || fail "Cannot save the launcher background"

failed=0
errors=$(mktemp "$cache_dir/wal/apply-errors.XXXXXX") || errors=""
trap '[ -z "$errors" ] || rm -f -- "$errors"' EXIT
if [ -n "$errors" ]; then
    # Tee only stderr, keeping stdout on fd 3. The pipeline waits for tee so
    # every diagnostic is captured before we read the component names.
    { "$config_dir/scripts/theming/apply-wal.sh" 9>&- 2>&1 1>&3 3>&- \
        | tee "$errors" 9>&- 3>&- >&2; } 3>&1 || failed=1
else
    "$config_dir/scripts/theming/apply-wal.sh" 9>&- || failed=1
fi
components=""
if [ -n "$errors" ]; then
    while IFS= read -r component; do
        components="${components:+$components, }$component"
    done < <(sed -n 's|^apply-wal: \([^/][^/]*\)/apply_wal_colors\.sh failed$|\1|p' "$errors")
    rm -f -- "$errors"
    errors=""
fi

# Waybar restyles itself when its colours file changes (reload_style_on_change).
# A full reload would rebuild the bar and briefly drop its reserved zone,
# resizing every tiled window.
# The settings panel reads the palette on demand; it has no resident consumer.

if [ "$failed" -ne 0 ]; then
    [ -z "$components" ] || fail "Colors were generated, but these components failed to update: $components."
    fail "Colors were generated, but some components failed to update. See the wallpaper command's stderr for details."
fi
# No success notification: the new wallpaper is the confirmation, and a toast
# would land on top of its transition. Failures still notify.
