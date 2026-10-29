#!/bin/bash
#
# One-click update setup
# Installs a root-owned copy of system-update-root.sh, then grants passwordless
# sudo for that installed copy, with no arguments, only. The update card can
# then run `pacman -Syu` in the background without a password prompt and
# without making a user-writable script root-equivalent. It also installs
# waybar-updates.hook, so the bar's count follows updates run anywhere.
# This installer still reads the user-writable source before invoking sudo, so
# review updates/system-update-root.sh before approving an installation or an
# upgrade.
#

SUDOERS_FILE="/etc/sudoers.d/system-update"
INSTALLED_HELPER="/usr/local/bin/system-update"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_SCRIPT="$SCRIPT_DIR/system-update-root.sh"
# A pacman hook that refreshes the bar's count after any transaction.
HOOK_SOURCE="$SCRIPT_DIR/waybar-updates.hook"
INSTALLED_HOOK="/etc/pacman.d/hooks/zz-waybar-updates.hook"

# The rule is written for $USER. Under `sudo` that is root, which would grant
# root a rule it does not need and leave the user without one.
if [[ "$EUID" -eq 0 ]]; then
    echo "✗ Run this as your own user, not with sudo: bash $SCRIPT_DIR/setup-sudo.sh" >&2
    echo "  It asks for your sudo password itself when it needs to." >&2
    exit 1
fi

echo "Setting up one-click system updates..."
echo ""

if [[ ! -f "$ROOT_SCRIPT" ]]; then
    echo "✗ $ROOT_SCRIPT not found"
    exit 1
fi

# The exact command sudo lists for this rule: the helper followed by "",
# sudoers' spelling of "no arguments allowed". The spelling is confirmed on
# first setup: the final check fails loudly if sudo lists it differently.
GRANTED_COMMAND="$INSTALLED_HELPER \"\""

listing_has_current_grant() {
    printf '%s\n' "$1" | awk -v command="$GRANTED_COMMAND" '
        {
            marker = "NOPASSWD: "
            position = index($0, marker)
            if (position == 0) next
            granted = substr($0, position + length(marker))
            count = split(granted, entries, /,/)
            for (i = 1; i <= count; i++) {
                sub(/^[[:space:]]+/, "", entries[i])
                sub(/[[:space:]]+$/, "", entries[i])
                if (entries[i] == command) found = 1
            }
        }
        END { exit !found }
    '
}

sudo_listing=$(sudo -n -l 2>/dev/null || true)
helper_current=false
grant_current=false

if [[ ! -L "$INSTALLED_HELPER" ]] &&
   cmp -s "$ROOT_SCRIPT" "$INSTALLED_HELPER" &&
   [[ "$(stat -c '%U:%G %a' "$INSTALLED_HELPER" 2>/dev/null)" = "root:root 755" ]]; then
    helper_current=true
fi
if listing_has_current_grant "$sudo_listing"; then
    grant_current=true
fi

# Build and validate a replacement rule only when the effective grant has
# drifted, so a configured run never asks for a password just to re-check.
tmpfile=""
trap '[[ -z "$tmpfile" ]] || rm -f "$tmpfile"' EXIT
if ! $grant_current; then
    tmpfile=$(mktemp)
    printf '%s ALL=(root) NOPASSWD: %s ""\n' "$USER" "$INSTALLED_HELPER" > "$tmpfile"
    if ! sudo visudo -c -f "$tmpfile" >/dev/null; then
        echo "✗ Generated sudoers rule failed validation"
        exit 1
    fi
fi

if $helper_current; then
    echo "✓ Root-owned helper is already current"
else
    if sudo install -m 0755 -o root -g root "$ROOT_SCRIPT" "$INSTALLED_HELPER"; then
        echo "✓ Installed root-owned helper at $INSTALLED_HELPER"
    else
        echo "✗ Failed to install root-owned helper"
        exit 1
    fi
fi

# Same test as the helper's: pacman runs the hook's Exec as root.
if [[ ! -L "$INSTALLED_HOOK" ]] && cmp -s "$HOOK_SOURCE" "$INSTALLED_HOOK" &&
   [[ "$(stat -c '%U:%G %a' "$INSTALLED_HOOK" 2>/dev/null)" = "root:root 644" ]]; then
    echo "✓ Bar refresh hook is already current"
elif sudo install -D -m 0644 -o root -g root "$HOOK_SOURCE" "$INSTALLED_HOOK"; then
    echo "✓ Installed $INSTALLED_HOOK"
else
    echo "✗ Failed to install the bar refresh hook"
    exit 1
fi

if $grant_current; then
    echo "✓ Passwordless sudo rule is already current"
else
    if sudo install -m 0440 -o root -g root "$tmpfile" "$SUDOERS_FILE"; then
        echo "✓ Installed $SUDOERS_FILE"
    else
        echo "✗ Failed to install sudoers file"
        exit 1
    fi
fi

# Verify the grant WITHOUT running the helper: running it would update the
# whole system as a side effect of setup. `sudo -l <command>` would succeed for
# any permitted command (wheel), passwordless or not, so check the listing
# for the NOPASSWD entry instead.
if listing_has_current_grant "$(sudo -n -l 2>/dev/null || true)"; then
    echo "✓ One-click updates are ready"
else
    echo "⚠ Passwordless sudo may not be working yet. Check that this lists a NOPASSWD entry for $INSTALLED_HELPER:"
    echo "  sudo -n -l"
    exit 1
fi
