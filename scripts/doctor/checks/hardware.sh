#!/bin/bash
#
# Host hardware truth: no tracked config names a display output that this
# machine does not have.
#
# Nothing is enumerated here. The valid set comes from the kernel, the
# occurrences come from `git ls-files -s`. A config file added tomorrow is
# covered the moment it is committed.
#
# WHY /sys/class/drm RATHER THAN hyprctl. The doctor must be runnable from a
# TTY with no compositor — that is exactly when a broken monitor config is
# worth diagnosing — and sysfs answers there. hyprctl does not.
#
# SEVERITY IS WARN, NEVER ERROR. Naming a connector that happens to be
# unplugged right now is legitimate: a docked laptop, a monitor switched off at
# the wall. The finding says the config is stale, not that the session is
# broken, and doctor.sh must not exit 1 on a machine whose session came up fine.
#
# WHAT IS DELIBERATELY NOT SCANNED:
#
#   *.md — README.md and docs/guide.md carry connector names as deliberate
#   examples of what a value looks like. This is the same reasoning that
#   already excludes docs/ from references.sh's literal-path scan.
#
#   docs/ — the specs and plans quote real connector names when recording what
#   was measured on a given machine.
#
#   scripts/doctor/ — this file's own pattern below, and its fixtures, are made
#   of connector names.
#
#   test/ directories, top-level or nested — fixtures name fake outputs on
#   purpose (a second display to disable, an output that disappeared), and
#   test.sh owns everything under them.
#
#   Tracked symlinks. Every one of them points into ~/.cache, where the content
#   is generated — waypaper/config.ini resolves to ~/.cache/waypaper-config.ini,
#   which is exactly where waypaper records a chosen connector. A finding there
#   would hand the user a hint telling them to edit a tracked symlink, which is
#   the opposite of this repo's cache-symlink invariant: generated state lives
#   in ~/.cache and is corrected by regenerating it, never by hand. Reporting a
#   file the user cannot correct misdirects rather than helps. The mode comes
#   from `git ls-files -s`, the same source of truth symlinks.sh derives from.
#
# Accepted limitations:
#
#   - The test/ skip keys on the directory name alone, so a live config kept
#     under a directory called test would go unscanned. test.sh already treats
#     every test/ directory as suite-owned, so no config belongs there.
#   - A connector name inside a comment reads the same as one in a live
#     setting. Distinguishing them means knowing the comment syntax of every
#     tracked file type, which is a worse trade than one occasional finding on
#     a line that was already documenting the stale value.
#
#   - The pattern has no left-hand word boundary, so a token ending in a
#     connector name matches: AUDP-3 yields DP-3. Fixing it needs a lookbehind,
#     which grep -oE does not have; a (^|[^A-Za-z]) prefix would instead capture
#     the boundary character into the token and break the comparison against the
#     present set. There are zero such occurrences in this tree, so the cost of
#     the workaround exceeds the cost of the gap.

# The DRM connector namespace, as the kernel spells it in
# /usr/include/libdrm/drm_mode.h. This is upstream vocabulary — the same kind
# of constant as DOCTOR_WAYBAR_ACTIONS in waybar.sh, and stale only on a kernel
# release, never on a change to this repo.
#
# It is the subset this repo plausibly encounters, not the whole namespace of
# 21. KNOWINGLY OMITTED, none of which any machine running this tree has:
# Composite, SVIDEO, Component, 9PinDIN, TV, DPI, Writeback, SPI, USB, Unknown.
# Adding one to a config without adding it here costs a missed WARN, never a
# false one — so the list fails safe, which is why it is worth keeping narrow
# rather than speculative.
#
# Alternation order is irrelevant: grep matches leftmost, and at offset 0 of
# eDP-1 only eDP can begin a match, so eDP-1 is never read as a bare DP-1.
# DisplayPort MST (Multi-Stream Transport) carries several downstream displays
# on one physical link. DRM names each downstream branch by appending `-<N>`,
# so a connector can be DP-1-1 (and its numeric suffix can repeat further down
# a daisy chain); matching only DP-1 would both invent false warnings and hide
# stale MST names when a plain DP-1 exists.
DOCTOR_DRM_CONNECTOR_RE='(eDP|DP|HDMI-A|HDMI-B|DVI-D|DVI-I|DVI-A|LVDS|DSI|VGA|Virtual)-[0-9]+(-[0-9]+)*'

# Overridable so the test suite can point the probe at a fake DRM tree instead
# of the running machine. Same seam, for the same reason, as BATTERY_SYSFS in
# scripts/waybar/battery.sh.
DOCTOR_DRM_SYSFS="${DOCTOR_DRM_SYSFS:-/sys/class/drm}"

# _hw_present_outputs — host probe, in its own function so tests can aim it.
#
# PRESENT, NOT CONNECTED. sysfs reports three states, and only `disconnected`
# is a definite absence: `unknown` comes from a driver that cannot do hotplug
# detect, and such a connector may well be driving a display right now. Treating
# unknown as present is what keeps this check from asserting something false —
# it costs a missed warning at worst, never a wrong one.
#
# Node names are card<N>-<CONNECTOR>; the card prefix is stripped so what comes
# back is the name Hyprland, hyprlock and awww all use. The strip is a
# shortest-match prefix removal, so a multi-dash name survives whole.
_hw_present_outputs() {
    local node base status
    for node in "$DOCTOR_DRM_SYSFS"/card*-*; do
        [ -r "$node/status" ] || continue
        read -r status < "$node/status" || continue
        [ "$status" = "disconnected" ] && continue
        base="${node##*/}"
        printf '%s\n' "${base#card*-}"
    done
}

check_hardware() {
    group "Hardware"

    local before
    before=$(doctor_findings)
    local present record mode file token

    present="$(_hw_present_outputs)"

    if [ -z "$present" ]; then
        note "no display output found under $DOCTOR_DRM_SYSFS — skipping the connector scan" \
             "run doctor.sh on the machine itself; a container has no DRM nodes to read"
        return 0
    fi

    # Process substitution, not a pipeline — see the contract note in lib.sh.
    # -z and -d '' because git C-quotes any path holding a non-ASCII or quote
    # character, and the quoted form names no file on disk.
    while IFS= read -r -d '' record; do
        mode="${record%% *}"
        # Generated content behind a tracked symlink — see the header.
        [ "$mode" = "120000" ] && continue
        # Everything past the first tab is the path, verbatim.
        file="${record#*$'\t'}"

        case "$file" in
            *.md|docs/*|scripts/doctor/*|test/*|*/test/*) continue ;;
        esac
        [ -f "$DOCTOR_ROOT/$file" ] || continue

        while IFS= read -r token; do
            [ -n "$token" ] || continue
            printf '%s\n' "$present" | grep -qxF -- "$token" && continue
            warn "$file names $token, which is not an output on this machine" \
                 "point $(doctor_q "$DOCTOR_ROOT/$file") at an output this machine has, or remove the name"
        done < <(grep -ohIE "$DOCTOR_DRM_CONNECTOR_RE" "$DOCTOR_ROOT/$file" 2>/dev/null | sort -u)
    done < <(git -C "$DOCTOR_ROOT" ls-files -sz 2>/dev/null)

    # ok is the all-clear and nothing else — gated on every severity, as
    # waybar.sh is, so a note added inside the scan cannot silently print a
    # green tick beside it.
    ok_if_clean "$before" "no tracked config names a disconnected output"
}
