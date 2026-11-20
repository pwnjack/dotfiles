#!/bin/bash
#
# SDDM Wallpaper Sudo Setup
# Installs a root-owned copy of update_sddm_root.sh, then grants passwordless
# sudo for that installed copy only. The wallpaper watcher can therefore sync
# in the background without making a user-writable script root-equivalent.
# The manual installer still reads that user-writable source before invoking
# sudo, so callers must review it before approving an installation or upgrade.
#

SUDOERS_FILE="/etc/sudoers.d/sddm-wallpaper"
INSTALLED_HELPER="/usr/local/bin/sddm-wallpaper-update"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_SCRIPT="$SCRIPT_DIR/update_sddm_root.sh"

# The rule is written for $USER. Under `sudo` that is root, which would replace
# the user's grant with a useless one for root, so refuse and say how to run it.
if [[ "$EUID" -eq 0 ]]; then
    echo "✗ Run this as your own user, not with sudo: bash $SCRIPT_DIR/setup-sudo.sh" >&2
    echo "  It asks for your sudo password itself when it needs to." >&2
    exit 1
fi

echo "Setting up passwordless sudo for SDDM wallpaper updates..."
echo ""

if [[ ! -f "$ROOT_SCRIPT" ]]; then
    echo "✗ $ROOT_SCRIPT not found"
    exit 1
fi

listing_has_current_grant() {
    local listing="$1"

    printf '%s\n' "$listing" | awk -v command="$INSTALLED_HELPER $USER" '
        {
            marker = "NOPASSWD: "
            position = index($0, marker)
            if (position == 0) next
            granted = substr($0, position + length(marker))
            count = split(granted, entries, /,/)
            for (i = 1; i <= count; i++) {
                sub(/^[[:space:]]+/, "", entries[i])
                sub(/[[:space:]]+$/, "", entries[i])
                if (entries[i] == "ALL" || entries[i] == command) found = 1
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
# drifted. A fully configured run must never ask for a password merely to
# validate the rule it already uses.
tmpfile=""
trap '[[ -z "$tmpfile" ]] || rm -f "$tmpfile"' EXIT
if ! $grant_current; then
    tmpfile=$(mktemp)
    printf '%s ALL=(root) NOPASSWD: %s %s\n' \
        "$USER" "$INSTALLED_HELPER" "$USER" > "$tmpfile"
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

# Test it
verify_ok=true
if sudo -n "$INSTALLED_HELPER" "$USER" 2>/dev/null; then
    echo "✓ Passwordless sudo is now working!"
    echo ""
    echo "The SDDM wallpaper has been updated to your current wallpaper."
else
    verify_ok=false
    echo "⚠ Passwordless sudo may not be working yet. Try running:"
    echo "  sudo $INSTALLED_HELPER $USER"
fi

$verify_ok || exit 1
