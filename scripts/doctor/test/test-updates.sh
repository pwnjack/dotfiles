# Tests for scripts/doctor/checks/updates.sh — sourced by run-tests.sh
#
# Sourced fragment, never executed directly, so it carries no shebang.
# shellcheck shell=bash

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/updates.sh"

upd_root="$DOCTOR_TEST_TMP/upd-root"
mkdir -p "$upd_root/updates"
upd_helper="$DOCTOR_TEST_TMP/upd-installed-helper"
cat > "$upd_root/updates/setup-sudo.sh" <<EOT
SUDOERS_FILE="/etc/sudoers.d/system-update"
INSTALLED_HELPER="$upd_helper"
EOT
printf '#!/bin/bash\necho helper\n' > "$upd_root/updates/system-update-root.sh"

upd_pacman=yes
upd_listing=""
upd_state=""

# Host probes are the only pieces replaced.
_upd_have_pacman() { [ "$upd_pacman" = yes ]; }
doctor_sudo_listing() { printf '%s\n' "$upd_listing"; }
doctor_file_state() { printf '%s' "$upd_state"; }
upd_default_present=no
_upd_orphan_present() { [ "$upd_default_present" = yes ]; }

upd_grant="User x may run the following commands on h:
    (root) NOPASSWD: $upd_helper \"\""

# Not set up at all.
rm -f "$upd_helper"; upd_listing=""; upd_state=""
DOCTOR_ROOT="$upd_root" run_check check_updates
assert_eq "$DOCTOR_WARNINGS" 1 "updates: not set up is one warning"
assert_eq "$DOCTOR_ERRORS" 0 "updates: not set up is not an error"
assert_contains "$CHECK_OUT" "updates/setup-sudo.sh" "updates: the hint names the setup script"

# Healthy.
cp "$upd_root/updates/system-update-root.sh" "$upd_helper"; upd_state="root:root 755"; upd_listing="$upd_grant"
DOCTOR_ROOT="$upd_root" run_check check_updates
assert_eq "$DOCTOR_WARNINGS$DOCTOR_ERRORS" "00" "updates: healthy has no findings"
assert_contains "$CHECK_OUT" "one-click updates are set up" "updates: healthy says so"

# Drift.
echo '# changed' >> "$upd_helper"
DOCTOR_ROOT="$upd_root" run_check check_updates
assert_contains "$CHECK_OUT" "differs from the tracked source" "updates: drift warns"
cp "$upd_root/updates/system-update-root.sh" "$upd_helper"

# Unsafe ownership.
upd_state="pwnjack:pwnjack 755"
DOCTOR_ROOT="$upd_root" run_check check_updates
assert_eq "$DOCTOR_ERRORS" 1 "updates: a user-owned NOPASSWD helper is an error"
upd_state="root:root 755"

# Symlink.
rm -f "$upd_helper"; ln -s /bin/true "$upd_helper"
DOCTOR_ROOT="$upd_root" run_check check_updates
assert_eq "$DOCTOR_ERRORS" 1 "updates: a symlinked helper is an error"
rm -f "$upd_helper"; cp "$upd_root/updates/system-update-root.sh" "$upd_helper"

# Grant missing.
upd_listing=""
DOCTOR_ROOT="$upd_root" run_check check_updates
assert_contains "$CHECK_OUT" "not in the effective passwordless sudo permissions" "updates: a missing grant warns"
upd_listing="$upd_grant"

# A blanket NOPASSWD: ALL entry also counts as a grant.
upd_listing="User x may run the following commands on h:
    (root) NOPASSWD: ALL"
DOCTOR_ROOT="$upd_root" run_check check_updates
assert_eq "$DOCTOR_WARNINGS$DOCTOR_ERRORS" "00" "updates: NOPASSWD ALL satisfies the grant"
upd_listing="$upd_grant"

# No pacman: nothing at all.
upd_pacman=no
DOCTOR_ROOT="$upd_root" run_check check_updates
assert_eq "$CHECK_OUT" "" "updates: hosts without pacman print nothing"
upd_pacman=yes

# A tree without the feature: nothing at all.
upd_saved_root="$upd_root"
upd_root="$DOCTOR_TEST_TMP/upd-empty-root"
mkdir -p "$upd_root"
DOCTOR_ROOT="$upd_root" run_check check_updates
assert_eq "$CHECK_OUT" "" "updates: a tree without updates/ prints nothing"

# Sources gone but a root helper still installed: a warning.
upd_default_present=yes
DOCTOR_ROOT="$upd_root" run_check check_updates
assert_eq "$DOCTOR_WARNINGS$DOCTOR_ERRORS" "10" "updates: an orphaned helper is one warning"
assert_contains "$CHECK_OUT" "no tracked source" "updates: the orphaned helper is named"
upd_default_present=no

# Half the feature present: an error, not silence.
mkdir -p "$upd_root/updates"
cp "$upd_saved_root/updates/system-update-root.sh" "$upd_root/updates/"
DOCTOR_ROOT="$upd_root" run_check check_updates
assert_eq "$DOCTOR_ERRORS" 1 "updates: a missing setup script is an error"
upd_root="$upd_saved_root"
