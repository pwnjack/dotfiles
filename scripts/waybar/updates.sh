#!/bin/bash
#
# Pending updates for waybar -- repo, AUR and Flatpak, one count.
#
# This module is the update notifier, and it does not duplicate the updater: a
# click opens the update card (scripts/hyprland/updates-popover.sh), and the
# terminal path for AUR updates is scripts/updates/terminal.sh.
#
# The count comes from the card's own planner, scripts/updates/updates-plan.sh,
# so the bar's number is the card's number. The planner owns the exit-status
# trap (checkupdates exits 2 for "none", paru -Qua exits 1) and the lock on
# the private sync DB; see its header. Its status means, here:
#
#   0   a plan on stdout: count it, hide at zero
#   3   pacman cannot resolve the upgrade: show the glyph alone, because that
#       is exactly when a terminal is needed
#   *   offline, lock timeout, no planner: hide, as a failed check always has
#
# The tooltip is quickshell/updates/model.mjs's tooltip(), run through
# scripts/updates/tooltip.mjs -- the card's copy, so the wording agrees too.
# If node fails, a one-line tooltip stands in: a tooltip error must never
# hide the module.
#
# UPDATES_PLAN_CMD, UPDATES_TOOLTIP, UPDATES_STATE_DIR and BAR_OPTIONS are the
# test seam; test-updates.sh drives them the way test-battery.sh drives
# BATTERY_SYSFS.
#

PLAN_CMD="${UPDATES_PLAN_CMD:-$HOME/.config/scripts/updates/updates-plan.sh}"
TOOLTIP="${UPDATES_TOOLTIP:-$HOME/.config/scripts/updates/tooltip.mjs}"

ICON=$'\U000f06b0'   # Nerd Font, Material Design: update (󰚰)

# The Bar page's mode (options/bar-updates): pending, or hidden. Hidden
# returns before the planner, whose checkupdates syncs a DB over the network.
BAR_OPTIONS="${BAR_OPTIONS:-$HOME/.config/options}"
mode=''
read -r mode 2>/dev/null < "$BAR_OPTIONS/bar-updates"
[ "$mode" = hidden ] && exit 0

# The update card's run state (scripts/updates/updates-run.sh writes it).
# While a run is active, show its progress and return BEFORE the planner.
# A finished run the card has not shown yet (ack != finishedAt) keeps a
# class so the result is not missed: restart replaces the module, attention
# marks the normal count.
STATE_DIR="${UPDATES_STATE_DIR:-${XDG_RUNTIME_DIR:-/run/user/$UID}/updates}"
run_status='' run_progress=0 run_finished=0 snap=''
if [ -r "$STATE_DIR/state.json" ]; then
    IFS=$'\t' read -r run_status run_progress run_finished < <(
        jq -r '[.status // "", (.progress // 0), (.finishedAt // 0)] | @tsv' "$STATE_DIR/state.json" 2>/dev/null)
    snap=$(jq -c . "$STATE_DIR/state.json" 2>/dev/null)
fi
[ -n "$snap" ] || snap=null
# Liveness comes from run.lock, not from state.json: the runner deletes the
# state right after taking the lock and the first snapshot follows a moment
# later, and after a SIGKILL the file still says running with the lock free.
# So a held lock means running (0% until a snapshot exists), and a "running"
# file with a free lock is stale.
# The probe reads /proc/locks (as quickshell/updates/shell.qml does) instead of
# trying the lock: a momentary flock -n here could make a starting runner find
# the lock taken and exit as busy.
lock_held() {
    local f=$1 maj min ino
    [ -e "$f" ] || return 1
    read -r maj min ino < <(stat -L -c '%Hd %Ld %i' -- "$f") || return 1
    grep -q " $(printf '%02x:%02x:%s' "$maj" "$min" "$ino") " /proc/locks 2>/dev/null
}
if lock_held "$STATE_DIR/run.lock"; then
    run_status=running
elif [ "$run_status" = running ]; then
    run_status=''
fi
run_seen=false
[ "$(cat "$STATE_DIR/ack" 2>/dev/null)" = "$run_finished" ] && run_seen=true

# tip <fallback> <input json> -- the tooltip from the shared model, or the
# fallback line when node or the model fails. The fallback is plain text with
# no markup characters, so it is valid Pango as it stands.
tip() {
    local out
    if out=$(printf '%s' "$2" | node "$TOOLTIP" 2>/dev/null) && [ -n "$out" ]; then
        printf '%s' "$out"
    else
        printf '%s' "$1"
    fi
}

# Nerd Font Material circle-slice-1..8, one per eighth of the run.
SLICES=($'\U000f0a9e' $'\U000f0a9f' $'\U000f0aa0' $'\U000f0aa1'
        $'\U000f0aa2' $'\U000f0aa3' $'\U000f0aa4' $'\U000f0aa5')
RESTART_ICON=$'\U000f0709'   # restart

if [ "$run_status" = running ]; then
    pct=$(awk -v p="$run_progress" 'BEGIN { v = int(p * 100); if (v < 0) v = 0; if (v > 99) v = 99; print v }')
    slice=${SLICES[$(( pct * 8 / 100 ))]}
    # Right after the runner takes the lock, state.json can still hold the
    # previous run's result; only a running snapshot describes this run (the
    # card applies the same guard).
    tooltip=$(tip "Updating · $pct%" "$(jq -nc --arg icon "$slice" --argjson pct "$pct" --argjson snap "$snap" \
        '{state: "running", icon: $icon, pct: $pct,
          snap: (if $snap != null and $snap.status == "running" then $snap else null end)}')")
    jq -nc --arg text "<span size=\"large\">$slice</span> $pct%" --arg tooltip "$tooltip" \
        '{text: $text, tooltip: $tooltip, class: "running"}'
    exit 0
fi
if [ "$run_status" = restart ] && ! $run_seen; then
    tooltip=$(tip "Restart to finish the update" "$(jq -nc --argjson snap "$snap" '{state: "restart", snap: $snap}')")
    jq -nc --arg text "<span size=\"large\">$RESTART_ICON</span>" --arg tooltip "$tooltip" \
        '{text: $text, tooltip: $tooltip, class: "restart"}'
    exit 0
fi
class=""
case "$run_status" in attention | failed) $run_seen || class=attention ;; esac

# The plan. stdout goes to a file and stderr is captured, because exit 3's
# reason is the planner's last stderr line -- the line the card shows too.
planfile=$(mktemp) || exit 0
trap 'rm -f "$planfile"' EXIT
reason=$("$PLAN_CMD" 2>&1 >"$planfile")
rc=$?
reason=${reason##*$'\n'}

if [ "$rc" -eq 3 ]; then
    tooltip=$(tip "Updates need a terminal" "$(jq -nc --arg icon "$ICON" --arg reason "$reason" \
        '{state: "blocked", icon: $icon, reason: $reason}')")
    jq -nc --arg text "<span size=\"large\">$ICON</span>" --arg tooltip "$tooltip" \
        '{text: $text, tooltip: $tooltip, class: "attention"}'
    exit 0
fi

plan=null total=0
if [ "$rc" -eq 0 ]; then
    plan=$(jq -c . "$planfile" 2>/dev/null)
    total=$(jq '(.repo | length) + (.aur | length) + (.flatpak // 0)' <<< "$plan" 2>/dev/null)
    [[ "$total" =~ ^[0-9]+$ ]] || { plan=null total=0; }
fi

# Nothing pending: print nothing and let waybar hide the module -- the idiom
# battery.sh and custom/media already use. The module APPEARING is the signal,
# which is what keeps this stateless with nothing to remember or expire.
if [ "$total" -eq 0 ]; then
    # An unseen failed run stays visible even with nothing pending (pacman
    # fine, Flatpak failed) or a failed check: the alert class is the only
    # trace of it.
    if [ -n "$class" ]; then
        tooltip=$(tip "The last update needs attention" "$(jq -nc --arg icon "$ICON" --argjson snap "$snap" \
            '{state: "attention", icon: $icon, snap: $snap}')")
        jq -nc --arg text "<span size=\"large\">$ICON</span>" --arg tooltip "$tooltip" \
            '{text: $text, tooltip: $tooltip, class: "attention"}'
    fi
    exit 0
fi

if [ -n "$class" ]; then
    input=$(jq -nc --arg icon "$ICON" --argjson snap "$snap" --argjson plan "$plan" \
        '{state: "attention", icon: $icon, snap: $snap, plan: $plan}')
else
    input=$(jq -nc --arg icon "$ICON" --argjson plan "$plan" --arg checked "$(date +%H:%M)" \
        '{state: "pending", icon: $icon, plan: $plan, checked: $checked}')
fi
fallback="$total update"
[ "$total" -eq 1 ] || fallback+=s
tooltip=$(tip "$fallback" "$input")

# The gap between glyph and count is set HERE, not in style.css: a waybar
# module is a single Pango label, so the stylesheet owns the gaps BETWEEN
# modules and the format string owns the one INSIDE.
#
# One plain space, and deliberately NOT the telemetry modules'
# letter_spacing='4096' + space. That attribute is what CREATES their gap
# rather than tightening it, so copying it verbatim moved the count further
# out. This glyph is a circular arrow with little ink on its right edge, where
# the cpu/disk glyphs are dense square blocks, so an equal metric gap reads
# wider here -- the same effect battery.sh documents in reverse when it takes
# two spaces to look equal.
text="<span size=\"large\">$ICON</span> $total"

jq -nc --arg text "$text" --arg tooltip "$tooltip" --arg class "$class" \
    '{text: $text, tooltip: $tooltip} + (if $class == "" then {} else {class: $class} end)'
