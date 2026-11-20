#!/bin/bash
#
# Tests for scripts/ssh/setup.sh.
#
# Standalone, exit 1 on any failure. Every case runs the script as a subprocess
# against its own throwaway HOME, with systemctl replaced by a stub on PATH that
# logs its arguments, so nothing touches the real ~/.ssh or user manager.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$TEST_DIR/setup.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../lib/assert.sh"

# The literal is the point: it is what ssh reads, unexpanded.
# shellcheck disable=SC2088
INC='Include ~/.config/ssh/config'

mkdir -p "$TMP/bin"
cat > "$TMP/bin/systemctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$STUB_LOG"
case "$*" in
    "--user cat "*) [ "${STUB_UNIT:-present}" = present ] ;;
    "--user enable "*) [ -z "${STUB_FAIL_ENABLE:-}" ] ;;
    *) exit 0 ;;
esac
STUB
chmod +x "$TMP/bin/systemctl"
export PATH="$TMP/bin:$PATH"
export STUB_LOG="$TMP/systemctl.log"

# A private copy of the two tracked files setup.sh reads, so nothing here can
# chmod the real repo. mk_repo <dir> builds one; TEST_REPO is what setup sees.
mk_repo() {
    mkdir -p "$1/hypr/config/setup" "$1/ssh"
    cp "$TEST_DIR/../../hypr/config/setup/envvars.lua" "$1/hypr/config/setup/"
    cp "$TEST_DIR/../../ssh/config" "$1/ssh/config"
    chmod 644 "$1/ssh/config"
}
mk_repo "$TMP/repo"
TEST_REPO="$TMP/repo"
# same <a> <b> -- "same" when the two files are byte-identical.
same() { if cmp -s -- "$1" "$2"; then echo same; else echo differ; fi; }
# expect_file <path> <old> -- write the Include line followed by <old>'s exact bytes.
expect_file() { { printf '%s\n' "$INC"; cat -- "$2"; } > "$1"; }

n=0
# fresh_home -- a new, empty HOME in $h.
fresh_home() { n=$((n + 1)); h="$TMP/home$n"; mkdir -p "$h"; }
# setup <args...> -- run the script against $h; sets $out and $rc.
setup() {
    : > "$STUB_LOG"
    out=$(HOME="$h" XDG_RUNTIME_DIR=/run/user/test SSH_SETUP_REPO="$TEST_REPO" bash "$SETUP" "$@" 2>&1) && rc=0 || rc=$?
}
mode() { stat -c %a -- "$1"; }
# existing_config <mode> -- a config with a Host block and no Include.
existing_config() {
    mkdir -p "$h/.ssh"
    printf 'Host example\n    User someone\n' > "$h/.ssh/config"
    chmod "$1" "$h/.ssh/config"
    cp -a "$h/.ssh/config" "$TMP/original$n"
}

# --- fresh machine -----------------------------------------------------------
fresh_home
setup --backup-dir "$h/bak"
assert_eq "$rc" 0 "fresh: exits 0"
assert_eq "$(mode "$h/.ssh")" 700 "fresh: ~/.ssh is created private"
assert_eq "$(mode "$h/.ssh/config")" 600 "fresh: the config is created private"
assert_eq "$(cat "$h/.ssh/config")" "$INC" "fresh: the config holds just the Include"
assert_absent "$h/bak" "fresh: nothing to back up"
assert_contains "$(cat "$STUB_LOG")" "--user enable --now ssh-agent.socket" \
    "fresh: the agent socket is enabled"
assert_contains "$(cat "$STUB_LOG")" \
    "--user set-environment SSH_AUTH_SOCK=/run/user/test/ssh-agent.socket" \
    "fresh: the running user manager gets SSH_AUTH_SOCK"

# --- existing config ---------------------------------------------------------
fresh_home
existing_config 640
setup --backup-dir "$h/bak"
assert_eq "$rc" 0 "existing: exits 0"
assert_eq "$(same "$TMP/original$n" "$h/bak/.ssh/config")" same \
    "existing: the backup is byte-for-byte the old file"
assert_eq "$(mode "$h/bak/.ssh/config")" 640 "existing: the backup keeps the mode"
assert_eq "$(head -n 1 "$h/.ssh/config")" "$INC" "existing: the Include comes first"
expect_file "$TMP/expected$n" "$TMP/original$n"
assert_eq "$(same "$TMP/expected$n" "$h/.ssh/config")" same \
    "existing: Include first, old bytes follow unchanged"
assert_eq "$(mode "$h/.ssh/config")" 640 "existing: the config keeps its mode"
assert_contains "$out" "$h/bak/.ssh/config" "existing: says where the backup went"

# --- second run is a no-op ---------------------------------------------------
cp -a "$h/.ssh/config" "$TMP/after$n"
setup --backup-dir "$h/bak2"
assert_eq "$rc" 0 "rerun: exits 0"
assert_eq "$(same "$TMP/after$n" "$h/.ssh/config")" same \
    "rerun: the config is unchanged"
assert_absent "$h/bak2" "rerun: no backup when nothing changes"

# --- Include present but not first -------------------------------------------
fresh_home
mkdir -p "$h/.ssh"
printf 'Host example\n%s\n' "$INC" > "$h/.ssh/config"
cp -a "$h/.ssh/config" "$TMP/original$n"
setup --backup-dir "$h/bak"
assert_eq "$rc" 0 "late include: exits 0"
assert_eq "$(head -n 1 "$h/.ssh/config")" "$INC" "late include: a copy is put first"
expect_file "$TMP/expected$n" "$TMP/original$n"
assert_eq "$(same "$TMP/expected$n" "$h/.ssh/config")" same "late include: old contents follow"
assert_eq "$(same "$TMP/original$n" "$h/bak/.ssh/config")" same "late include: backed up first"

# --- --no-backup and the default backup dir ----------------------------------
fresh_home
existing_config 600
setup --no-backup
assert_eq "$rc" 0 "no-backup: exits 0"
assert_contains "$out" "--no-backup given; not backing up $h/.ssh/config" "no-backup: says so"
assert_eq "$(head -n 1 "$h/.ssh/config")" "$INC" "no-backup: still changed"
assert_eq "$(compgen -G "$h/.config-backup-*" || echo none)" none "no-backup: no backup made"

fresh_home
existing_config 600
setup
assert_eq "$rc" 0 "default: exits 0"
assert_eq "$(compgen -G "$h/.config-backup-*/.ssh/config" >/dev/null && echo yes)" yes \
    "default: backs up under ~/.config-backup-<timestamp>"
bdir=$(basename "$(compgen -G "$h/.config-backup-*" | head -n 1)")
assert_eq "$([[ $bdir =~ ^\.config-backup-[0-9]{8}-[0-9]{6}$ ]] && echo match)" match \
    "default: the backup dir name carries a timestamp"

# --- --dry-run writes nothing ------------------------------------------------
fresh_home
existing_config 600
before=$(find "$h" -printf '%p %m %s %T@\n' | sort)
setup --dry-run --backup-dir "$h/bak"
after=$(find "$h" -printf '%p %m %s %T@\n' | sort)
assert_eq "$rc" 0 "dry run: exits 0"
assert_eq "$after" "$before" "dry run: nothing under HOME changes"
assert_eq "$(grep -vc '^--user cat ' "$STUB_LOG")" 0 "dry run: systemctl is only queried"
assert_contains "$out" "would" "dry run: says what it would do"
assert_contains "$out" "dry run complete; nothing was changed" "dry run: closes as a dry run"
assert_not_contains "$out" "Log out" "dry run: no re-login note"

fresh_home
setup --dry-run
assert_eq "$rc" 0 "dry run, fresh: exits 0"
assert_absent "$h/.ssh" "dry run: a fresh HOME gets no ~/.ssh"

# --- no unit -----------------------------------------------------------------
fresh_home
STUB_UNIT=absent setup
assert_eq "$rc" 0 "no unit: exits 0"
assert_contains "$out" "skipping the agent" "no unit: says it skips the agent"
assert_eq "$(cat "$h/.ssh/config")" "$INC" "no unit: the Include is still written"
assert_not_contains "$(cat "$STUB_LOG")" "enable" "no unit: nothing is enabled"

# --- symlinked config is left alone ------------------------------------------
fresh_home
mkdir -p "$h/.ssh"
printf 'Host x\n' > "$h/elsewhere"
ln -s "$h/elsewhere" "$h/.ssh/config"
setup --backup-dir "$h/bak"
assert_eq "$rc" 1 "symlink: exits 1"
assert_contains "$(cat "$STUB_LOG")" "--user set-environment SSH_AUTH_SOCK=" \
    "symlink: the later steps still run"
assert_contains "$out" "Log out" "symlink: the closing message still prints"
assert_eq "$(readlink "$h/.ssh/config")" "$h/elsewhere" "symlink: the link is untouched"
assert_eq "$(cat "$h/elsewhere")" "Host x" "symlink: its target is untouched"
assert_contains "$out" "$INC" "symlink: names the line to add"
assert_absent "$h/bak" "symlink: no backup made"

# --- symlinked config that already includes the fragment ---------------------
fresh_home
mkdir -p "$h/.ssh"
printf '%s\nHost x\n' "$INC" > "$h/elsewhere"
cp -a "$h/elsewhere" "$TMP/target$n"
ln -s "$h/elsewhere" "$h/.ssh/config"
setup --backup-dir "$h/bak"
assert_eq "$rc" 0 "symlink+include: exits 0"
assert_contains "$out" "already includes the tracked fragment" "symlink+include: says so"
assert_eq "$(readlink "$h/.ssh/config")" "$h/elsewhere" "symlink+include: link untouched"
assert_eq "$(same "$TMP/target$n" "$h/elsewhere")" same "symlink+include: target untouched"
assert_absent "$h/bak" "symlink+include: no backup made"

fresh_home
mkdir -p "$h/.ssh"
printf '%s\r\nHost x\n' "$INC" > "$h/elsewhere"
cp -a "$h/elsewhere" "$TMP/target$n"
ln -s "$h/elsewhere" "$h/.ssh/config"
setup --backup-dir "$h/bak"
assert_eq "$rc" 0 "symlink+CRLF include: exits 0"
assert_eq "$(same "$TMP/target$n" "$h/elsewhere")" same "symlink+CRLF include: target untouched"

# --- first line compared as ssh reads it: trailing space and CR ignored ------
for variant in 'crlf:\r' 'trailing space:  '; do
    fresh_home
    mkdir -p "$h/.ssh"
    printf "%s${variant#*:}\nHost x\n" "$INC" > "$h/.ssh/config"
    cp -a "$h/.ssh/config" "$TMP/original$n"
    setup --backup-dir "$h/bak"
    assert_eq "$rc" 0 "${variant%%:*}: exits 0"
    assert_eq "$(same "$TMP/original$n" "$h/.ssh/config")" same "${variant%%:*}: config unchanged"
    assert_absent "$h/bak" "${variant%%:*}: no backup"
done

# --- config shapes -----------------------------------------------------------
fresh_home
mkdir -p "$h/.ssh"
printf 'Host a\n    User b' > "$h/.ssh/config"
cp -a "$h/.ssh/config" "$TMP/original$n"
setup --backup-dir "$h/bak"
expect_file "$TMP/expected$n" "$TMP/original$n"
assert_eq "$rc" 0 "no trailing newline: exits 0"
assert_eq "$(same "$TMP/expected$n" "$h/.ssh/config")" same \
    "no trailing newline: no newline is added to the old last line"

fresh_home
mkdir -p "$h/.ssh"
: > "$h/.ssh/config"
setup --backup-dir "$h/bak"
printf '%s\n' "$INC" > "$TMP/expected$n"
assert_eq "$rc" 0 "empty config: exits 0"
assert_eq "$(same "$TMP/expected$n" "$h/.ssh/config")" same "empty config: holds just the Include"

fresh_home
mkdir -p "$h/.ssh"
chmod 755 "$h/.ssh"
setup --backup-dir "$h/bak"
assert_eq "$rc" 0 "ssh dir without config: exits 0"
assert_eq "$(mode "$h/.ssh")" 755 "ssh dir without config: the directory mode is kept"
assert_eq "$(mode "$h/.ssh/config")" 600 "ssh dir without config: config created private"
assert_absent "$h/bak" "ssh dir without config: nothing to back up"

# --- the included fragment must not be group/world writable ------------------
mk_repo "$TMP/repo664"
chmod 664 "$TMP/repo664/ssh/config"
TEST_REPO="$TMP/repo664"
fresh_home
setup --dry-run
assert_eq "$(mode "$TEST_REPO/ssh/config")" 664 "fragment: dry run leaves the mode"
assert_contains "$out" "chmod go-w" "fragment: dry run says it would fix it"
setup
assert_eq "$rc" 0 "fragment: exits 0"
assert_eq "$(mode "$TEST_REPO/ssh/config")" 644 "fragment: a 664 fragment becomes 644"
assert_contains "$out" "go-w" "fragment: says it fixed the mode"
TEST_REPO="$TMP/repo"

# --- a failed enable does not stop the Include -------------------------------
fresh_home
STUB_FAIL_ENABLE=1 setup
assert_eq "$rc" 1 "enable fails: exits 1"
assert_contains "$out" "ssh: could not enable ssh-agent.socket; the Include is still set up" \
    "enable fails: says so"
assert_eq "$(cat "$h/.ssh/config")" "$INC" "enable fails: the Include is still written"

# --- an existing backup is never overwritten ---------------------------------
fresh_home
existing_config 600
mkdir -p "$h/bak/.ssh"
printf 'keep\n' > "$h/bak/.ssh/config"
setup --backup-dir "$h/bak"
assert_eq "$rc" 1 "backup exists: exits 1"
assert_contains "$(cat "$STUB_LOG")" "--user set-environment SSH_AUTH_SOCK=" \
    "backup exists: the later steps still run"
assert_eq "$(same "$TMP/original$n" "$h/.ssh/config")" same "backup exists: config untouched"
assert_eq "$(cat "$h/bak/.ssh/config")" keep "backup exists: old backup untouched"
assert_contains "$out" "$h/bak/.ssh/config" "backup exists: names the path"

# --- envvars.lua without the SSH_AUTH_SOCK line ------------------------------
mkdir -p "$TMP/repoenv/hypr/config/setup" "$TMP/repoenv/ssh"
printf 'return function() end\n' > "$TMP/repoenv/hypr/config/setup/envvars.lua"
cp "$TMP/repo/ssh/config" "$TMP/repoenv/ssh/config"
TEST_REPO="$TMP/repoenv"
fresh_home
setup
assert_eq "$rc" 0 "no env line: exits 0"
assert_not_contains "$(cat "$STUB_LOG")" "set-environment" "no env line: not pushed"
assert_contains "$out" "skipping set-environment" "no env line: says it skips"
assert_contains "$out" "Log out" "re-login note prints even when set-environment is skipped"
TEST_REPO="$TMP/repo"

# --- commented-out Lua line is ignored ----------------------------------------
mk_repo "$TMP/repocmt"
printf '    -- hl.env("SSH_AUTH_SOCK", runtime .. "/old")\nlocal runtime = 1\nhl.env("SSH_AUTH_SOCK", runtime .. "/new.socket", true)\n' \
    > "$TMP/repocmt/hypr/config/setup/envvars.lua"
TEST_REPO="$TMP/repocmt"
fresh_home
setup
assert_contains "$(cat "$STUB_LOG")" "SSH_AUTH_SOCK=/run/user/test/new.socket" \
    "comment: the live line wins and the dbus flag is accepted"
printf '    -- hl.env("SSH_AUTH_SOCK", runtime .. "/old")\n' > "$TMP/repocmt/hypr/config/setup/envvars.lua"
setup
assert_contains "$out" "skipping set-environment" "comment: only a commented line counts as absent"
TEST_REPO="$TMP/repo"

# --- AddKeysToAgent already in the user's config -----------------------------
fresh_home
mkdir -p "$h/.ssh"
printf 'Host x\n   addkeystoagent no\n' > "$h/.ssh/config"
setup --backup-dir "$h/bak"
assert_eq "$rc" 0 "AddKeysToAgent: exits 0"
assert_contains "$out" "takes" "AddKeysToAgent: the precedence notice prints"
assert_contains "$out" "precedence" "AddKeysToAgent: says the tracked value wins"
assert_eq "$(head -n 1 "$h/.ssh/config")" "$INC" "AddKeysToAgent: still proceeds"
fresh_home
existing_config 600
setup --backup-dir "$h/bak"
assert_not_contains "$out" "precedence" "no AddKeysToAgent: no notice"

# --- AddKeysToAgent yes does not conflict ------------------------------------
fresh_home
mkdir -p "$h/.ssh"
printf 'Host x\n  AddKeysToAgent YES\n' > "$h/.ssh/config"
setup --backup-dir "$h/bak"
assert_not_contains "$out" "precedence" "AddKeysToAgent yes: no notice"
assert_eq "$(head -n 1 "$h/.ssh/config")" "$INC" "AddKeysToAgent yes: still proceeds"

# --- restore command ---------------------------------------------------------
fresh_home
existing_config 600
setup --backup-dir "$h/bak"
assert_contains "$out" "cp -a $h/bak/.ssh/config $h/.ssh/config" "backup: prints the restore command"

# a backup dir with a space: the printed command restores the file when eval'd
fresh_home
existing_config 600
setup --backup-dir "$h/my bak"
cmd=$(printf '%s\n' "$out" | sed -n 's/^ssh: to restore: //p')
assert_contains "$cmd" "my\\ bak" "restore: the path is quoted"
rm -f "$h/.ssh/config"
(eval "$cmd")
assert_eq "$(same "$TMP/original$n" "$h/.ssh/config")" same "restore: the printed command restores the file"
fresh_home
existing_config 600
setup --dry-run --backup-dir "$h/bak"
assert_not_contains "$out" "to restore" "dry run: no restore command"

# --- dry run wording ---------------------------------------------------------
fresh_home
setup --dry-run
assert_contains "$out" "ssh: would enable ssh-agent.socket" "dry run: says would enable"
assert_not_contains "$out" "ssh: enabling" "dry run: does not claim to enable"

# --- bad arguments -----------------------------------------------------------
fresh_home
setup --nonsense
assert_eq "$rc" 2 "args: an unknown option exits 2"
setup --backup-dir
assert_eq "$rc" 2 "args: --backup-dir without a value exits 2"
setup --backup-dir --no-backup
assert_eq "$rc" 2 "args: --backup-dir refuses an option as its value"
assert_absent "$h/--no-backup" "args: no directory was created"

test_summary "ssh setup"
