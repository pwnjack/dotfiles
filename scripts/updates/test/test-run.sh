#!/bin/bash
#
# Tests for scripts/updates/updates-run.sh and fold.mjs.
#
# A fake helper replaces sudo + /usr/local/bin/system-update (UPDATES_SUDO=none,
# UPDATES_HELPER), so no root and no network are involved. UPDATES_SIGNAL=none
# keeps the suite from signalling a live Waybar.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$TEST_DIR/../updates-run.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../../lib/assert.sh"

export UPDATES_SUDO=none UPDATES_SIGNAL=none UPDATES_FLATPAK=no-such-flatpak
export UPDATES_KERNEL=6.0.0-test

# helper <exit> <line>... — a fake root helper printing the lines.
helper() {
    local code=$1
    shift
    {
        echo '#!/bin/bash'
        local line
        for line in "$@"; do printf 'echo %q\n' "$line"; done
        echo "exit $code"
    } > "$TMP/helper"
    chmod +x "$TMP/helper"
}

# run_case — a fresh state dir and modules dir (with the running kernel present).
run_case() {
    rm -rf "$TMP/state" "$TMP/modules"
    mkdir -p "$TMP/modules/$UPDATES_KERNEL"
    UPDATES_HELPER="$TMP/helper" UPDATES_STATE_DIR="$TMP/state" UPDATES_MODULES_DIR="$TMP/modules" \
        bash "$RUNNER"
    echo $? > "$TMP/status"
}
state() { cat "$TMP/state/state.json" 2>/dev/null; }

echo "updates-run.sh"

helper 0 '@@phase download' ':: Starting full system upgrade...' 'Packages (1) foo-1-2' \
    '@@phase install' ':: Processing package changes...' 'upgrading foo...'
run_case
assert_eq "$(cat "$TMP/status")" 0 "a successful run exits 0"
assert_json_field "$(state)" .status "done" "success ends done"
assert_json_field "$(state)" .progress 1 "success fills the bar"
assert_json_field "$(state)" .total 1 "the package total reaches the state"
assert_eq "$(tail -n1 "$TMP/state/run.log")" "@@end" "run.log ends with @@end"
left=$(ls "$TMP/state/state.json.tmp" 2>/dev/null)
assert_eq "$left" "" "no temporary file is left behind"

# Restart: the running kernel's module directory disappears during the run.
cat > "$TMP/helper" <<EOF
#!/bin/bash
rm -rf "$TMP/modules/$UPDATES_KERNEL"
mkdir -p "$TMP/modules/7.2.9-1-cachyos"
echo ':: Processing package changes...'
echo 'upgrading linux-cachyos...'
EOF
chmod +x "$TMP/helper"
run_case
assert_json_field "$(state)" .status restart "a replaced running kernel asks for a restart"
assert_json_field "$(state)" .restart 7.2.9-1-cachyos "the restart names the new kernel"

helper 1 'checking for file conflicts...' 'error: failed to commit transaction (conflicting files)' \
    'foo: /usr/bin/foo exists in filesystem (owned by bar)'
run_case
assert_json_field "$(state)" .status attention "a conflict before the transaction needs attention"
assert_json_field "$(state)" .errorKind pacman "and is pacman's"

# A stale acknowledgement from the previous run is cleared at start.
helper 0 'upgrading foo...'
mkdir -p "$TMP/state"
echo 123 > "$TMP/state/ack"
UPDATES_HELPER="$TMP/helper" UPDATES_STATE_DIR="$TMP/state" UPDATES_MODULES_DIR="$TMP/modules" bash "$RUNNER"
left=$(ls "$TMP/state/ack" 2>/dev/null)
assert_eq "$left" "" "a new run clears the old acknowledgement"

# Lock: a second runner while one is active exits 75 and leaves state alone.
rm -rf "$TMP/state"; mkdir -p "$TMP/modules/$UPDATES_KERNEL"
printf '#!/bin/bash\nsleep 2\n' > "$TMP/helper"; chmod +x "$TMP/helper"
UPDATES_HELPER="$TMP/helper" UPDATES_STATE_DIR="$TMP/state" UPDATES_MODULES_DIR="$TMP/modules" bash "$RUNNER" &
first=$!
for _ in $(seq 50); do [ -e "$TMP/state/state.json" ] && break; sleep 0.05; done
assert_json_field "$(state)" .status running "the fold publishes a running snapshot before any line"
before=$(state)
UPDATES_HELPER="$TMP/helper" UPDATES_STATE_DIR="$TMP/state" UPDATES_MODULES_DIR="$TMP/modules" bash "$RUNNER"
assert_eq "$?" 75 "a second runner exits 75 while one is active"
assert_eq "$(state)" "$before" "and does not touch the state"
wait "$first"

# --- fold failure, stale state, flavour, sudo, flatpak, missing @@end ---

FOLD_JS="$TEST_DIR/../fold.mjs"
# A fold that dies at once the first time it runs, then behaves.
cat > "$TMP/fold-once" <<EOF
#!/bin/bash
if [ ! -e "$TMP/fold-ran" ]; then touch "$TMP/fold-ran"; exit 1; fi
exec node "$FOLD_JS" "\$@"
EOF
# A fold that always dies.
printf '#!/bin/bash\nexit 1\n' > "$TMP/fold-dead"
# A fold that is slow to publish its first snapshot.
printf '#!/bin/bash\nsleep 0.6\nexec node "%s" "$@"\n' "$FOLD_JS" > "$TMP/fold-slow"
chmod +x "$TMP/fold-once" "$TMP/fold-dead" "$TMP/fold-slow"

slow_helper() {
    printf '#!/bin/bash\nsleep 0.3\necho "upgrading foo..."\nexit 0\n' > "$TMP/helper"
    chmod +x "$TMP/helper"
}

echo "a dead fold"
slow_helper
rm -f "$TMP/fold-ran"
UPDATES_FOLD="$TMP/fold-once" run_case
assert_eq "$(cat "$TMP/status")" 0 "a dead fold does not fail the runner"
assert_eq "$(grep -c '^upgrading foo' "$TMP/state/run.log")" 1 "the helper's later output still reaches run.log"
assert_eq "$(tail -n1 "$TMP/state/run.log")" "@@end" "and the log still ends with @@end"
assert_json_field "$(state)" .status "done" "a dead fold is redone from run.log"

slow_helper
UPDATES_FOLD="$TMP/fold-dead" run_case
assert_eq "$(tail -n1 "$TMP/state/run.log")" "@@end" "with no working fold the log is still complete"
assert_json_field "$(state)" .status attention "and a minimal terminal state replaces running"
left=$(ls "$TMP/state/state.json.fallback" 2>/dev/null)
assert_eq "$left" "" "the fallback leaves no temporary file"

echo "a new run hides the previous result"
slow_helper
rm -rf "$TMP/state"; mkdir -p "$TMP/state" "$TMP/modules/$UPDATES_KERNEL"
echo '{"status":"done","progress":1}' > "$TMP/state/state.json"
UPDATES_FOLD="$TMP/fold-slow" UPDATES_HELPER="$TMP/helper" UPDATES_STATE_DIR="$TMP/state" \
    UPDATES_MODULES_DIR="$TMP/modules" bash "$RUNNER" &
first=$!
sleep 0.3
gone=$(ls "$TMP/state/state.json" 2>/dev/null)
assert_eq "$gone" "" "the old state.json is gone while the new run starts"
wait "$first"
assert_json_field "$(state)" .status "done" "and the new run publishes its own"

echo "restart picks the running kernel's flavour"
rm -rf "$TMP/state" "$TMP/modules"
mkdir -p "$TMP/modules/7.2.8-2-cachyos"
cat > "$TMP/helper" <<EOF
#!/bin/bash
rm -rf "$TMP/modules/7.2.8-2-cachyos"
mkdir -p "$TMP/modules/7.2.9-1-cachyos" "$TMP/modules/7.2.10-1-cachyos"
sleep 0.05
mkdir -p "$TMP/modules/7.3.0-1-cachyos-lts"
EOF
chmod +x "$TMP/helper"
UPDATES_KERNEL=7.2.8-2-cachyos UPDATES_HELPER="$TMP/helper" UPDATES_STATE_DIR="$TMP/state" \
    UPDATES_MODULES_DIR="$TMP/modules" bash "$RUNNER"
assert_json_field "$(state)" .restart 7.2.10-1-cachyos "the newest directory of the same flavour wins, not the newest mtime"

echo "sudo"
printf '#!/bin/bash\necho "sudo: a password is required"\nexit 1\n' > "$TMP/helper"
chmod +x "$TMP/helper"
run_case
assert_json_field "$(state)" .status attention "a sudo refusal needs attention"
assert_json_field "$(state)" .errorKind sudo "and is reported as sudo's"

echo "a stream with no @@end"
# The fold itself must end a stream that stops early; fed directly.
mkdir -p "$TMP/fold"
printf '%s\n' ':: Starting full system upgrade...' '@@helper-exit 0' \
    | UPDATES_SIGNAL=none node "$FOLD_JS" "$TMP/fold/state.json" 1000
assert_json_field "$(cat "$TMP/fold/state.json")" .status "done" "a stream ending without @@end is closed by the fold"

echo "final bar signal"
# A fake pkill (first on PATH, so fold.mjs's signals reach it too) records
# whether run.lock is held at each call; the last call is the runner's own.
mkdir -p "$TMP/pbin"
cat > "$TMP/pbin/pkill" <<'FAKE'
#!/bin/bash
echo "$*" > "$TMP_SIGNAL/args"
if flock -n "$TMP_SIGNAL/state/run.lock" true; then echo free > "$TMP_SIGNAL/lock"; else echo held > "$TMP_SIGNAL/lock"; fi
FAKE
chmod +x "$TMP/pbin/pkill"
export TMP_SIGNAL="$TMP/sig"
helper 0 ':: Processing package changes...' 'upgrading foo...'
rm -rf "$TMP/sig" "$TMP/state" "$TMP/modules"
mkdir -p "$TMP/sig" "$TMP/modules/$UPDATES_KERNEL" "$TMP/state"
ln -s "$TMP/state" "$TMP/sig/state"
env -u UPDATES_SIGNAL PATH="$TMP/pbin:$PATH" UPDATES_HELPER="$TMP/helper" UPDATES_STATE_DIR="$TMP/state" \
    UPDATES_MODULES_DIR="$TMP/modules" bash "$RUNNER"
assert_eq "$(cat "$TMP/sig/lock" 2>/dev/null)" free "the final bar signal comes after run.lock is released"
assert_eq "$(cat "$TMP/sig/args" 2>/dev/null)" "-x -RTMIN+9 waybar" "and is the bar's refresh signal"
rm -rf "$TMP/sig"

echo "flatpak"
cat > "$TMP/flatpak" <<'EOF'
#!/bin/bash
case "$1" in
list) echo org.example.App ;;
update)
    echo "Updating org.example.App"
    [ -n "${FAKE_FLATPAK_SLEEP-}" ] && sleep "$FAKE_FLATPAK_SLEEP"
    exit "${FAKE_FLATPAK_EXIT:-0}" ;;
esac
EOF
chmod +x "$TMP/flatpak"
helper 0 ':: Processing package changes...' 'upgrading foo...'
UPDATES_FLATPAK="$TMP/flatpak" run_case
assert_json_field "$(state)" .status "done" "a successful Flatpak phase ends done"
assert_eq "$(grep -c '^@@flatpak-exit 0$' "$TMP/state/run.log")" 1 "and records its exit"
FAKE_FLATPAK_EXIT=1 UPDATES_FLATPAK="$TMP/flatpak" run_case
assert_json_field "$(state)" .status attention "a failing Flatpak phase needs attention"
assert_json_field "$(state)" .errorKind flatpak "and is Flatpak's"
FAKE_FLATPAK_SLEEP=5 UPDATES_FLATPAK_TIMEOUT=0.3 UPDATES_FLATPAK="$TMP/flatpak" run_case
assert_eq "$(grep -c '^@@flatpak-exit 124$' "$TMP/state/run.log")" 1 "a stalled Flatpak update is stopped by the timeout"
assert_json_field "$(state)" .status attention "and does not leave the run at 98%"

test_summary "updates-run"
