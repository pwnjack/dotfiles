# Tests for scripts/doctor/checks/ssh.sh — sourced by run-tests.sh
#
# Sourced fragment, never executed directly, so it carries no shebang.
# shellcheck shell=bash

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/ssh.sh"

ssh_root="$DOCTOR_TEST_TMP/ssh-root"
ssh_home="$DOCTOR_TEST_TMP/ssh-home"
mkdir -p "$ssh_root/hypr/config/setup" "$ssh_root/scripts/ssh" "$ssh_root/ssh" "$ssh_home/.ssh"
echo 'AddKeysToAgent yes' > "$ssh_root/ssh/config"
# Quoted heredoc: the line must reach the fixture literally.
cat > "$ssh_root/hypr/config/setup/envvars.lua" <<'EOT'
return function()
    local runtime = os.getenv("XDG_RUNTIME_DIR")
    if runtime and runtime ~= "" then hl.env("SSH_AUTH_SOCK", runtime .. "/ssh-agent.socket") end
end
EOT
cat > "$ssh_root/scripts/ssh/setup.sh" <<'EOT'
SSH_AGENT_UNIT="ssh-agent.socket"
INCLUDE_LINE="Include ~/.config/ssh/config"
EOT
# shellcheck disable=SC2088
ssh_include='Include ~/.config/ssh/config'
ssh_expected="/run/user/test/ssh-agent.socket"

ssh_enabled=yes
ssh_present=yes
ssh_bus=yes
ssh_live=yes
ssh_session="$ssh_expected"
ssh_mode=644
ssh_rundir=/run/user/test

# Host probes are the only pieces replaced.
_ssh_unit_enabled() { [ "$ssh_enabled" = yes ]; }
_ssh_user_bus() { [ "$ssh_bus" = yes ]; }
_ssh_unit_present() { [ "$ssh_present" = yes ]; }
_ssh_socket_live() { [ "$ssh_live" = yes ] && [ "$1" = "$ssh_expected" ]; }
_ssh_home() { printf '%s' "$ssh_home"; }
_ssh_runtime_dir() { printf '%s' "$ssh_rundir"; }
_ssh_session_sock() { printf '%s' "$ssh_session"; }
_ssh_file_mode() { [ "$1" = "$ssh_root/ssh/config" ] && printf '%s' "$ssh_mode"; }

ssh_run() {
    doctor_reset
    DOCTOR_ROOT="${1:-$ssh_root}" check_ssh > "$DOCTOR_TEST_TMP/ssh.out" 2>&1
    ssh_out=$(cat "$DOCTOR_TEST_TMP/ssh.out")
}
ssh_healthy() {
    ssh_enabled=yes; ssh_present=yes; ssh_bus=yes; ssh_live=yes; ssh_session="$ssh_expected"; ssh_mode=644; ssh_rundir=/run/user/test
    rm -f "$ssh_home/.ssh/real" "$ssh_home/.ssh/config"
    printf '%s\nHost x\n' "$ssh_include" > "$ssh_home/.ssh/config"
}

# Not applicable: no envvars.lua, or one without the SSH_AUTH_SOCK line.
mkdir -p "$DOCTOR_TEST_TMP/ssh-bare"
ssh_run "$DOCTOR_TEST_TMP/ssh-bare"
assert_eq "$ssh_out" "" "ssh: a tree without envvars.lua prints nothing"
mkdir -p "$DOCTOR_TEST_TMP/ssh-novar/hypr/config/setup"
echo 'return function() end' > "$DOCTOR_TEST_TMP/ssh-novar/hypr/config/setup/envvars.lua"
ssh_run "$DOCTOR_TEST_TMP/ssh-novar"
assert_eq "$ssh_out" "" "ssh: an envvars.lua without SSH_AUTH_SOCK prints nothing"

# Commented-out Lua lines are ignored; only a commented line counts as absent.
mkdir -p "$DOCTOR_TEST_TMP/ssh-cmt/hypr/config/setup"
cat > "$DOCTOR_TEST_TMP/ssh-cmt/hypr/config/setup/envvars.lua" <<'EOT'
    -- hl.env("SSH_AUTH_SOCK", runtime .. "/old")
return function() end
EOT
ssh_run "$DOCTOR_TEST_TMP/ssh-cmt"
assert_eq "$ssh_out" "" "ssh: a commented-out line counts as absent"
cat > "$DOCTOR_TEST_TMP/ssh-cmt/hypr/config/setup/envvars.lua" <<'EOT'
    -- hl.env("SSH_AUTH_SOCK", runtime .. "/old")
    if runtime then hl.env("SSH_AUTH_SOCK", runtime .. "/new.socket") end
EOT
assert_eq "$(_ssh_socket_name "$DOCTOR_TEST_TMP/ssh-cmt/hypr/config/setup/envvars.lua")" "/new.socket" \
    "ssh: the live line wins over a commented one above it"
cat > "$DOCTOR_TEST_TMP/ssh-cmt/hypr/config/setup/envvars.lua" <<'EOT'
    if runtime then hl.env("SSH_AUTH_SOCK", runtime .. "/new.socket", true) end
EOT
assert_eq "$(_ssh_socket_name "$DOCTOR_TEST_TMP/ssh-cmt/hypr/config/setup/envvars.lua")" "/new.socket" \
    "ssh: the optional dbus flag is accepted"

# The real tree: the parse must keep working against what is tracked.
assert_eq "$(_ssh_socket_name "$REPO_DIR/hypr/config/setup/envvars.lua")" "/ssh-agent.socket" \
    "ssh: the real envvars.lua yields the socket name"
assert_eq "$(doctor_assignment "$REPO_DIR/scripts/ssh/setup.sh" SSH_AGENT_UNIT)" "ssh-agent.socket" \
    "ssh: the real setup.sh yields SSH_AGENT_UNIT"
assert_eq "$(doctor_assignment "$REPO_DIR/scripts/ssh/setup.sh" INCLUDE_LINE)" "$ssh_include" \
    "ssh: the real setup.sh yields INCLUDE_LINE"

# Healthy.
ssh_healthy
ssh_run
assert_eq "$DOCTOR_WARNINGS$DOCTOR_ERRORS$DOCTOR_NOTICES" "000" "ssh: healthy has no findings"
assert_contains "$ssh_out" "SSH agent" "ssh: prints its group"
assert_contains "$ssh_out" "passphrase once per login" "ssh: healthy says so"

# ssh ignores trailing whitespace on the Include line, CR included.
ssh_healthy; printf '%s\r\nHost x\n' "$ssh_include" > "$ssh_home/.ssh/config"
ssh_run
assert_eq "$DOCTOR_WARNINGS$DOCTOR_ERRORS$DOCTOR_NOTICES" "000" "ssh: a CRLF first line is healthy"
ssh_healthy; printf '%s  \nHost x\n' "$ssh_include" > "$ssh_home/.ssh/config"
ssh_run
assert_eq "$DOCTOR_WARNINGS$DOCTOR_ERRORS$DOCTOR_NOTICES" "000" "ssh: a trailing-space first line is healthy"

# Unit not enabled.
ssh_healthy; ssh_enabled=no; ssh_live=no
ssh_run
assert_eq "$DOCTOR_WARNINGS" 1 "ssh: a disabled unit is one warning, the socket check is skipped"
assert_contains "$ssh_out" "ssh-agent.socket is not enabled" "ssh: names the unit"
assert_contains "$ssh_out" "scripts/ssh/setup.sh" "ssh: the hint runs the setup script"
assert_not_contains "$ssh_out" "passphrase once per login" "ssh: no ok beside a finding"

# Enabled, nothing listening.
ssh_healthy; ssh_live=no
ssh_run
assert_eq "$DOCTOR_WARNINGS" 1 "ssh: a dead socket is one warning"
assert_contains "$ssh_out" "$ssh_expected" "ssh: names the expanded socket path"
assert_contains "$ssh_out" "systemctl --user restart ssh-agent.socket" "ssh: the hint restarts the unit"

# Config missing, then Include not first.
ssh_healthy; rm -f "$ssh_home/.ssh/config"
ssh_run
assert_eq "$DOCTOR_WARNINGS" 1 "ssh: a missing config is one warning"
assert_contains "$ssh_out" "does not exist" "ssh: says the config is missing"
assert_not_contains "$ssh_out" "does not start with" "ssh: a missing file is not a wrong first line"
ssh_healthy; printf 'Host x\n%s\n' "$ssh_include" > "$ssh_home/.ssh/config"
ssh_run
assert_eq "$DOCTOR_WARNINGS" 1 "ssh: an Include that is not first is one warning"

# ssh refuses an Include target that is group or world writable.
ssh_healthy; ssh_mode=664
ssh_run
assert_eq "$DOCTOR_WARNINGS" 1 "ssh: a group-writable fragment is one warning"
assert_contains "$ssh_out" "chmod go-w" "ssh: the hint removes the write bits"
assert_contains "$ssh_out" "$ssh_root/ssh/config" "ssh: names the fragment"
assert_not_contains "$ssh_out" "passphrase once per login" "ssh: no ok beside the mode warning"
ssh_healthy; ssh_mode=644
ssh_run
assert_eq "$DOCTOR_WARNINGS" 0 "ssh: a 644 fragment is healthy"

# The current shell predates the setup.
ssh_healthy; ssh_session=""
ssh_run
assert_eq "$DOCTOR_WARNINGS$DOCTOR_NOTICES" "01" "ssh: a stale session is a note, not a warning"
assert_contains "$ssh_out" "log out and back in" "ssh: the note says what to do"
assert_not_contains "$ssh_out" "passphrase once per login" "ssh: no ok beside the note"

# Another agent in this shell: a note without logout advice.
ssh_healthy; ssh_session="/tmp/ssh-XXXX/agent.1"
ssh_run
assert_eq "$DOCTOR_WARNINGS$DOCTOR_NOTICES" "01" "ssh: a foreign agent is a note"
assert_contains "$ssh_out" "another agent at /tmp/ssh-XXXX/agent.1" "ssh: names the other agent"
assert_not_contains "$ssh_out" "log out" "ssh: no logout advice for a foreign agent"

# Unit file absent: setup.sh cannot clear it, so no hint.
ssh_healthy; ssh_present=no; ssh_enabled=no
ssh_run
assert_eq "$DOCTOR_WARNINGS" 1 "ssh: a missing unit is one warning"
assert_contains "$ssh_out" "ssh-agent.socket is not installed (it ships with openssh)" "ssh: says it is not installed"
assert_not_contains "$ssh_out" "not enabled" "ssh: not reported as merely disabled"
assert_not_contains "$ssh_out" "scripts/ssh/setup.sh" "ssh: no setup hint for a missing unit"

# Setup script lost its assignments.
ssh_healthy
cp "$ssh_root/scripts/ssh/setup.sh" "$DOCTOR_TEST_TMP/ssh-setup.bak"
echo '# emptied' > "$ssh_root/scripts/ssh/setup.sh"
ssh_run
assert_eq "$DOCTOR_WARNINGS" 1 "ssh: underivable settings are one warning"
assert_contains "$ssh_out" "cannot derive" "ssh: says it cannot derive them"
cp "$DOCTOR_TEST_TMP/ssh-setup.bak" "$ssh_root/scripts/ssh/setup.sh"

# A duplicated assignment is as underivable as a missing one.
printf 'SSH_AGENT_UNIT="a.socket"\nSSH_AGENT_UNIT="b.socket"\nINCLUDE_LINE="x"\n' > "$ssh_root/scripts/ssh/setup.sh"
ssh_healthy
ssh_run
assert_eq "$DOCTOR_WARNINGS" 1 "ssh: a duplicated SSH_AGENT_UNIT is one warning"
assert_contains "$ssh_out" "cannot derive" "ssh: a duplicate cannot be derived"
cp "$DOCTOR_TEST_TMP/ssh-setup.bak" "$ssh_root/scripts/ssh/setup.sh"

# A warning silences the stale-session note.
ssh_healthy; ssh_enabled=no; ssh_session=""
ssh_run
assert_eq "$DOCTOR_WARNINGS$DOCTOR_NOTICES" "10" "ssh: no session note beside a warning"

# No fragment in the tree: nothing to check the mode of.
ssh_healthy; ssh_mode=664
mv "$ssh_root/ssh/config" "$DOCTOR_TEST_TMP/ssh-frag.bak"
ssh_run
assert_eq "$DOCTOR_WARNINGS" 0 "ssh: a missing fragment draws no mode warning"
mv "$DOCTOR_TEST_TMP/ssh-frag.bak" "$ssh_root/ssh/config"

# No XDG_RUNTIME_DIR (su, sudo -u, cron): the socket cannot be judged.
ssh_healthy; ssh_rundir=""; ssh_live=no; ssh_session=""
ssh_run
assert_eq "$DOCTOR_WARNINGS$DOCTOR_NOTICES" "01" "ssh: no runtime dir is one note, no warning"
assert_contains "$ssh_out" "no user session bus in this shell" "ssh: the note says why"
assert_not_contains "$ssh_out" "/ssh-agent.socket" "ssh: no invented socket path"
assert_not_contains "$ssh_out" "passphrase once per login" "ssh: no ok without a runtime dir"
ssh_healthy; ssh_rundir=""; ssh_mode=664
ssh_run
assert_eq "$DOCTOR_WARNINGS" 1 "ssh: the fragment mode is still checked without a runtime dir"

# A symlinked ~/.ssh/config: setup.sh leaves it alone, so the hint names the target.
ssh_healthy
printf '%s\nHost x\n' "$ssh_include" > "$ssh_home/.ssh/real"
rm -f "$ssh_home/.ssh/config"
ln -s real "$ssh_home/.ssh/config"
ssh_run
assert_eq "$DOCTOR_WARNINGS$DOCTOR_NOTICES" "00" "ssh: a symlink to a good target is healthy"
printf 'Host x\n' > "$ssh_home/.ssh/real"
ssh_run
assert_eq "$DOCTOR_WARNINGS" 1 "ssh: a symlink to a bad target is one warning"
assert_contains "$ssh_out" "is a symlink whose target does not start with" "ssh: says it is a symlink"
assert_contains "$ssh_out" "add that line at the top of" "ssh: the hint is not the setup script"
assert_contains "$ssh_out" "$ssh_home/.ssh/real" "ssh: the hint names the target"
assert_not_contains "$ssh_out" "scripts/ssh/setup.sh" "ssh: setup.sh cannot clear a symlink"

# An unreadable config.
ssh_healthy
printf '%s\n' "$ssh_include" > "$ssh_home/.ssh/config"
chmod 000 "$ssh_home/.ssh/config"
ssh_run
chmod 600 "$ssh_home/.ssh/config"
assert_eq "$DOCTOR_WARNINGS" 1 "ssh: an unreadable config is one warning"
assert_contains "$ssh_out" "is not readable" "ssh: says it is unreadable"
assert_contains "$ssh_out" "chmod u+r" "ssh: the hint restores read access"
assert_not_contains "$ssh_out" "Permission denied" "ssh: no raw bash error"

# No runtime dir means no user bus either: the unit cannot be judged.
ssh_healthy; ssh_rundir=""; ssh_enabled=no
ssh_run
assert_eq "$DOCTOR_WARNINGS$DOCTOR_NOTICES" "01" "ssh: no runtime dir skips the unit check"
assert_contains "$ssh_out" "cannot check the agent unit or socket" "ssh: the note names the unit too"

# A dangling symlink whose directory is missing still names where it points.
ssh_healthy
rm -f "$ssh_home/.ssh/config"
ln -s "$DOCTOR_TEST_TMP/nonexistent-dir/cfg" "$ssh_home/.ssh/config"
ssh_run
assert_eq "$DOCTOR_WARNINGS" 1 "ssh: a dangling symlink is one warning"
assert_contains "$ssh_out" "$DOCTOR_TEST_TMP/nonexistent-dir/cfg" "ssh: the hint names the dangling target"

# No reachable user bus (runtime dir set): not "unit not installed".
ssh_healthy; ssh_bus=no; ssh_present=no; ssh_enabled=no; ssh_live=no
ssh_run
assert_eq "$DOCTOR_WARNINGS$DOCTOR_NOTICES" "01" "ssh: no user bus is one note, no warning"
assert_contains "$ssh_out" "no user session bus in this shell" "ssh: the note names the bus"
assert_not_contains "$ssh_out" "not installed" "ssh: no false not-installed"
