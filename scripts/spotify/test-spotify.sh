#!/bin/bash
#
# Tests for scripts/spotify/launch.sh and scripts/spotify/setup.sh.
#
# Standalone, exit 1 on any failure. Every case runs the script as a subprocess
# against its own throwaway HOME and client directory, with spotify-launcher,
# spicetify, curl, pgrep and notify-send replaced by stubs on PATH that append
# to one call log, so the order of steps is checkable and nothing touches the
# real client, network or desktop.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCH="$TEST_DIR/launch.sh"
SETUP="$TEST_DIR/setup.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=scripts/lib/assert.sh
# shellcheck disable=SC1091
. "$TEST_DIR/../lib/assert.sh"

mkdir -p "$TMP/bin"
export CALLS="$TMP/calls"

# spotify-launcher: --no-exec "updates" (a fresh client, no marker) when
# STUB_UPDATE is set; anything else is the final start, logged and done.
cat >"$TMP/bin/spotify-launcher" <<'STUB'
#!/bin/bash
if [ "$1" = --no-exec ]; then
    echo "update" >>"$CALLS"
    if [ -n "${STUB_UPDATE:-}" ]; then
        rm -rf "$SPOTIFY_INSTALL_DIR"
        mkdir -p "$SPOTIFY_INSTALL_DIR/Apps"
        : >"$SPOTIFY_INSTALL_DIR/Apps/xpui.spa"
    fi
    exit 0
fi
echo "start $*" >>"$CALLS"
[ -z "${STUB_FDS:-}" ] || ls -l "/proc/$$/fd" >>"$CALLS"
STUB
# spicetify: restore packs the client back into xpui.spa, backup apply
# unpacks it; both rebuild Apps/ whole, as the real one does (os.RemoveAll).
# STUB_SPICETIFY_FAIL makes every call fail.
cat >"$TMP/bin/spicetify" <<'STUB'
#!/bin/bash
echo "spicetify $*" >>"$CALLS"
[ -z "${STUB_SPICETIFY_FAIL:-}" ] || exit 1
apps="$SPOTIFY_INSTALL_DIR/Apps"
case "$*" in
    *restore*) rm -rf "$apps"; mkdir -p "$apps"; : >"$apps/xpui.spa" ;;
    *"backup apply"*)
        [ -z "${STUB_PREFS:-}" ] || grep '^app\.last-launched-version=' "$STUB_PREFS" >>"$CALLS" || true
        rm -rf "$apps"; mkdir -p "$apps/xpui" ;;
esac
STUB
# curl: "downloads" the fake SpotX below to the -o path, unless STUB_CURL_FAIL.
cat >"$TMP/bin/curl" <<'STUB'
#!/bin/bash
echo "curl ${*: -1}" >>"$CALLS"
[ -z "${STUB_CURL_FAIL:-}" ] || exit 22
while [ $# -gt 0 ]; do [ "$1" = -o ] && { cp "$FAKE_SPOTX" "$2"; exit 0; }; shift; done
exit 2
STUB
cat >"$TMP/bin/pgrep" <<'STUB'
#!/bin/bash
[ -n "${STUB_RUNNING:-}" ] || { [ -n "${STUB_RUNNING_FILE:-}" ] && [ -e "$STUB_RUNNING_FILE" ]; }
STUB
cat >"$TMP/bin/notify-send" <<'STUB'
#!/bin/bash
echo "notify $*" >>"$CALLS"
STUB
chmod +x "$TMP/bin"/*
# The fake SpotX refuses an unpacked client, as the real one does.
cat >"$TMP/spotx.sh" <<'STUB'
echo "spotx $*" >>"$CALLS"
[ -z "${STUB_SPOTX_FAIL:-}" ] || exit 1
[ -f "$SPOTIFY_INSTALL_DIR/Apps/xpui.spa" ] || exit 1
# The real one logs these lines, then ends on terminal escapes and no newline.
# N/A is what it prints when it cannot ask the binary; it then names the
# version it read from xpui.js.
case ${STUB_SPOTX_VERSION:-1.2.96.518} in
    N/A) printf '%s\n' "Latest supported version: 1.3.4.258" "Detected client version: N/A" \
            "✔ Detected Spotify ${STUB_SPOTX_XPUI:-1.2.96.518}" ;;
    *) printf '%s\n' "Latest supported version: 1.3.4.258" \
            "Detected client version: ${STUB_SPOTX_VERSION:-1.2.96.518}" ;;
esac
printf '\033[?25l\033[?25h'
STUB
export FAKE_SPOTX="$TMP/spotx.sh"
export PATH="$TMP/bin:$PATH"
export SPOTX_URL="https://example.invalid/spotx.sh"

n=0
# fresh <state> -- a new HOME and client in $h; <state> is patched (marker),
# stock (xpui.spa) or unpacked (Spicetify applied: xpui/, no xpui.spa).
fresh() {
    n=$((n + 1)); h="$TMP/home$n"
    export SPOTIFY_INSTALL_DIR="$h/client"
    mkdir -p "$SPOTIFY_INSTALL_DIR/Apps"
    case $1 in
        patched) : >"$SPOTIFY_INSTALL_DIR/Apps/xpui.spa"; : >"$SPOTIFY_INSTALL_DIR/.spotx-patched" ;;
        stock) : >"$SPOTIFY_INSTALL_DIR/Apps/xpui.spa" ;;
        unpacked) mkdir -p "$SPOTIFY_INSTALL_DIR/Apps/xpui" ;;
    esac
}
# spicetify_setup -- give $h a Spicetify config, which is what turns it on.
spicetify_setup() { mkdir -p "$h/.config/spicetify"; : >"$h/.config/spicetify/config-xpui.ini"; }
# launch <args...> -- run the wrapper against $h; sets $rc and $calls.
launch() {
    : >"$CALLS"
    HOME="$h" XDG_CONFIG_HOME="$h/.config" XDG_STATE_HOME="$h/.local/state" XDG_DATA_HOME="$h/data" \
        bash "$LAUNCH" "$@" >/dev/null 2>&1 && rc=0 || rc=$?
    calls=$(cat "$CALLS")
}
marker() { if [ -e "$SPOTIFY_INSTALL_DIR/.spotx-patched" ]; then echo yes; else echo no; fi; }

# --- already patched ---------------------------------------------------------
fresh patched
launch spotify:track:x
assert_eq "$calls" $'update\nstart --skip-update spotify:track:x' \
    "patched: updates, then starts with the URI; nothing is patched"

# --- an update wiped the patch -----------------------------------------------
fresh patched
spicetify_setup
STUB_UPDATE=1 launch
assert_eq "$(printf '%s\n' "$calls" | grep -v '^notify')" \
"update
curl $SPOTX_URL
spotx --noninteractive --nocolor -f -P $SPOTIFY_INSTALL_DIR
spicetify -q -n backup apply
start --skip-update" "updated: SpotX, then Spicetify on top, then start"
assert_eq "$(marker)" yes "updated: the marker is written after success"
assert_contains "$calls" "notify -a Spotify -i spotify-launcher Patching Spotify" "updated: a toast says it is patching"
assert_not_contains "$calls" "may be incomplete" "updated: a supported client gets no version warning"
launch
assert_eq "$(grep -c '^spotx \|^spicetify ' <<<"$calls")" 0 \
    "updated: the next start after a full SpotX + Spicetify run patches nothing"
spicetify -q -n restore
launch
assert_eq "$(grep -c '^spotx ' <<<"$calls")" 0 \
    "updated: a manual spicetify restore does not trigger SpotX again"

# --- Spicetify applied, SpotX never run (this machine's first run) -----------
fresh unpacked
spicetify_setup
launch
assert_eq "$(printf '%s\n' "$calls" | grep '^spicetify\|^spotx' | cut -d' ' -f1-4)" \
"spicetify -q -n restore
spotx --noninteractive --nocolor -f
spicetify -q -n backup" "unpacked: restore first, so SpotX sees xpui.spa"
assert_eq "$(marker)" yes "unpacked: the marker is written"

# --- a client newer than SpotX supports ------------------------------------
fresh stock
STUB_SPOTX_VERSION=1.3.10.1 launch
assert_eq "$(marker)" yes "newer client: SpotX exited 0, so the client is marked"
assert_contains "$calls" "SpotX may be incomplete" "newer client: a warning toast"
fresh stock
STUB_SPOTX_VERSION=N/A launch
assert_not_contains "$calls" "may be incomplete" "unknown version (N/A): no false warning"
fresh stock
STUB_SPOTX_VERSION=N/A STUB_SPOTX_XPUI=1.3.10.1 launch
assert_contains "$calls" "may be incomplete" "N/A, then a newer version read from xpui.js: warned"

# --- no Spicetify set up -----------------------------------------------------
fresh stock
launch
assert_not_contains "$calls" "spicetify" "no config: Spicetify is never called"
assert_eq "$(marker)" yes "no config: SpotX alone marks the client patched"

# --- Spicetify takes its backup version from prefs ----------------------------
prefs_setup() {
    prefs="$h/.config/spotify/prefs"
    mkdir -p "$(dirname "$prefs")"
    printf 'before=unchanged\napp.last-launched-version="1.2.96.518"\nafter=unchanged' >"$prefs"
    cp "$prefs" "$h/prefs.before"
}
launcher_state() {
    mkdir -p "$h/data/spotify-launcher"
    printf '{"version": "%s", "last_update_check": {}}\n' "$1" >"$h/data/spotify-launcher/state.json"
}
fresh stock
spicetify_setup
prefs_setup
launcher_state '1:1.3.4.258.gc60b10b0946a'
# shellcheck disable=SC2016
# Keep $HOME literal so the wrapper must expand Spicetify's path.
printf 'prefs_path = $HOME/.config/spotify/prefs\n' >"$h/.config/spicetify/config-xpui.ini"
STUB_PREFS="$prefs" launch
assert_eq "$rc" 0 "backup version: patching succeeds"
assert_eq "$(sed -n '/^spicetify -q -n backup apply$/{n;p;}' <<<"$calls")" \
    'app.last-launched-version="1.3.4.258.gc60b10b0946a"' \
    "backup version: Spicetify sees the installed version without its epoch"
sed 's/1.2.96.518/1.3.4.258.gc60b10b0946a/' "$h/prefs.before" >"$h/prefs.expected"
assert_eq "$(cmp -s "$prefs" "$h/prefs.expected"; echo $?)" 0 \
    "backup version: only the version changes, including no final newline"
assert_eq "$(stat -c %a "$prefs")" "$(stat -c %a "$h/prefs.before")" "backup version: prefs permissions preserved"
assert_eq "$(find "$(dirname "$prefs")" -name 'prefs.*' -print)" '' "backup version: no temporary prefs left behind"
fresh stock
spicetify_setup
prefs_setup
printf 'prefs_path = ~/.config/spotify/prefs\n' >"$h/.config/spicetify/config-xpui.ini"
launch
assert_eq "$(cmp -s "$prefs" "$h/prefs.before"; echo $?)" 0 "missing launcher state: prefs unchanged"
assert_contains "$(cat "$h/.local/state/spotify/patch.log")" "== exit 0" "missing launcher state: patching succeeds"
fresh stock
spicetify_setup
prefs_setup
launcher_state '1.3.4.258'
printf 'prefs_path = ~/.config/spotify/prefs\n' >"$h/.config/spicetify/config-xpui.ini"
printf 'unrelated=value\r\nlast=no newline' >"$prefs"
cp "$prefs" "$h/prefs.before"
launch
assert_eq "$(cmp -s "$prefs" "$h/prefs.before"; echo $?)" 0 "missing prefs key: byte-identical"
assert_contains "$(cat "$h/.local/state/spotify/patch.log")" "== exit 0" "missing prefs key: patching succeeds"
fresh stock
prefs_setup
launcher_state '1:1.3.4.258.gc60b10b0946a'
launch
assert_eq "$(cmp -s "$prefs" "$h/prefs.before"; echo $?)" 0 "no Spicetify config: prefs unchanged"
for version in '' 'not-a-version' '1.2.3.gxyz' '1..2' '1.2.3;bad'; do
    fresh stock
    spicetify_setup
    prefs_setup
    launcher_state "$version"
    printf 'prefs_path = ~/.config/spotify/prefs\n' >"$h/.config/spicetify/config-xpui.ini"
    launch
    assert_eq "$(cmp -s "$prefs" "$h/prefs.before"; echo $?)" 0 "invalid version '$version': prefs unchanged"
    assert_contains "$(cat "$h/.local/state/spotify/patch.log")" "== exit 0" "invalid version '$version': patching succeeds"
done
fresh stock
spicetify_setup
prefs_setup
launcher_state '1.3.4.258'
printf 'prefs_path = ~/.config/spotify/prefs\n' >"$h/.config/spicetify/config-xpui.ini"
launch
assert_contains "$(cat "$prefs")" 'app.last-launched-version="1.3.4.258"' \
    "backup version: tilde path and version without epoch or hash are accepted"
fresh stock
spicetify_setup
prefs_setup
launcher_state '1.3.4.258'
mv "$prefs" "$h/real-prefs"
ln -s "$h/real-prefs" "$prefs"
printf 'prefs_path = ~/.config/spotify/prefs  \n' >"$h/.config/spicetify/config-xpui.ini"
launch
assert_eq "$([ -L "$prefs" ] && echo link)" link "backup version: a symlinked prefs stays a symlink"
assert_contains "$(cat "$h/real-prefs")" 'app.last-launched-version="1.3.4.258"' \
    "backup version: the link's target is stamped, despite trailing spaces in prefs_path"
for missing in version prefs_path prefs; do
    fresh stock
    spicetify_setup
    prefs_setup
    launcher_state '1:1.3.4.258'
    printf 'prefs_path = ~/.config/spotify/prefs\n' >"$h/.config/spicetify/config-xpui.ini"
    case "$missing" in
        version) printf '{"last_update_check": {}}\n' >"$h/data/spotify-launcher/state.json" ;;
        prefs_path) : >"$h/.config/spicetify/config-xpui.ini" ;;
        prefs) rm "$prefs" ;;
    esac
    launch
    if [ "$missing" = prefs ]; then
        if [ -e "$prefs" ]; then exists=yes; else exists=no; fi
        assert_eq "$exists" no "missing prefs: never created"
    else
        assert_eq "$(cmp -s "$prefs" "$h/prefs.before"; echo $?)" 0 "missing $missing: prefs unchanged"
    fi
    assert_contains "$(cat "$h/.local/state/spotify/patch.log")" "== exit 0" "missing $missing: patching succeeds"
done

# --- failures never block Spotify --------------------------------------------
fresh stock
STUB_CURL_FAIL=1 launch
assert_eq "$(grep -c '^spotx ' <<<"$calls")" 0 "offline: SpotX does not run"
assert_contains "$calls" "start --skip-update" "offline: Spotify still starts"
assert_contains "$calls" "-u critical Spotify started without SpotX" "offline: a critical toast"
assert_eq "$(marker)" no "offline: no marker, so the next launch retries"
assert_contains "$(cat "$h/.local/state/spotify/patch.log")" "== exit 1" "offline: the log records the failure"

fresh stock
STUB_SPOTX_FAIL=1 launch
assert_contains "$calls" "start --skip-update" "SpotX fails: Spotify still starts"
assert_eq "$(marker)" no "SpotX fails: no marker"
assert_contains "$calls" "force-update" "SpotX fails: the toast names the reset"
assert_contains "$(cat "$h/.local/state/spotify/patch.log")" $'\n== exit 1' \
    "SpotX fails: the log's own lines start on a fresh line"

# --- a themed client that cannot be patched keeps its theme -------------------
fresh unpacked
spicetify_setup
STUB_CURL_FAIL=1 launch
assert_not_contains "$calls" "spicetify" "offline, themed: Spicetify is never touched"
fresh unpacked
spicetify_setup
STUB_SPOTX_FAIL=1 launch
assert_eq "$(printf '%s\n' "$calls" | grep '^spicetify\|^spotx' | cut -d' ' -f1-4)" \
"spicetify -q -n restore
spotx --noninteractive --nocolor -f
spicetify -q -n apply" "SpotX fails after restore: the theme is applied again"

fresh stock
spicetify_setup
STUB_SPICETIFY_FAIL=1 launch
assert_contains "$calls" "spotx" "Spicetify fails: SpotX ran"
assert_eq "$(marker)" yes "Spicetify fails: SpotX is marked applied, so it is not retried"
assert_contains "$calls" "Spicetify theme not applied" "Spicetify fails: its own toast"
assert_not_contains "$calls" "-u critical" "Spicetify fails: not reported as SpotX failing"
assert_contains "$calls" "start --skip-update" "Spicetify fails: Spotify still starts"
STUB_SPICETIFY_FAIL=1 launch
assert_eq "$(grep -c '^spotx ' <<<"$calls")" 0 "Spicetify fails: the next start does not re-run SpotX"

# --- a running Spotify is left alone -----------------------------------------
fresh stock
STUB_RUNNING=1 launch spotify:album:y
assert_eq "$calls" "start --skip-update spotify:album:y" \
    "running: no update, no patch; the URI goes to the running instance"

# --- a launch that waited on the lock re-checks ------------------------------
# A sibling holds the lock (patching); Spotify appears before it lets go.
fresh stock
: >"$CALLS"
mkdir -p "$h/.local/state/spotify"
exec 8>"$h/.local/state/spotify/patch.lock"
flock 8
HOME="$h" XDG_CONFIG_HOME="$h/.config" XDG_STATE_HOME="$h/.local/state" XDG_DATA_HOME="$h/data" \
    STUB_RUNNING_FILE="$h/running" bash "$LAUNCH" spotify:x >/dev/null 2>&1 8>&- &
waiter=$!
: >"$h/running"
exec 8>&-
wait "$waiter"
assert_eq "$(cat "$CALLS")" "start --skip-update spotify:x" \
    "lock: the waiting launch finds Spotify running and neither updates nor patches"

# --- the lock is not inherited by Spotify ------------------------------------
fresh patched
STUB_FDS=1 launch
assert_contains "$calls" "start --skip-update" "lock: Spotify started"
assert_not_contains "$calls" "patch.lock" "lock: fd 9 is closed before exec (patched)"
fresh stock
STUB_FDS=1 launch
assert_contains "$calls" "spotx" "lock: the patch path ran"
assert_not_contains "$calls" "patch.lock" "lock: fd 9 is closed before exec (after patching)"

# --- setup: the desktop entry --------------------------------------------------
cat >"$TMP/system.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Spotify (Launcher)
TryExec=spotify-launcher
Exec=spotify-launcher %U
MimeType=x-scheme-handler/spotify;

[Desktop Action play]
Name=Play
Exec=spotify-launcher --play
EOF
setup() {
    out=$(HOME="$h" XDG_DATA_HOME="$h/data" SPOTIFY_DESKTOP_SRC="$TMP/system.desktop" \
        SPOTIFY_SETUP_REPO="$TMP/my repo" bash "$SETUP" "$@" 2>&1) && rc=0 || rc=$?
}
entry() { cat "$h/data/applications/spotify-launcher.desktop" 2>/dev/null; }
fresh stock
setup --dry-run
assert_eq "$rc" 0 "setup dry run: exits 0"
assert_eq "$(entry)" "" "setup dry run: writes nothing"
setup
assert_eq "$rc" 0 "setup: exits 0"
assert_contains "$(entry)" "Exec=\"$TMP/my repo/scripts/spotify/launch.sh\" %U" \
    "setup: Exec runs the wrapper, quoted"
assert_contains "$(entry)" "MimeType=x-scheme-handler/spotify;" "setup: keeps the rest of the entry"
assert_eq "$(entry | grep -c '^Exec="')" 1 "setup: exactly one Exec runs the wrapper"
assert_contains "$(entry)" "Exec=spotify-launcher --play" "setup: a desktop action keeps its own Exec"
setup
assert_contains "$out" "is current" "setup: a second run changes nothing"
out=$(HOME="$h" XDG_DATA_HOME="$h/data" SPOTIFY_DESKTOP_SRC="$TMP/system.desktop" \
    SPOTIFY_SETUP_REPO='/a$b' bash "$SETUP" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "setup: refuses a path it cannot quote"
out=$(HOME="$h" XDG_DATA_HOME="$h/data" SPOTIFY_DESKTOP_SRC="$TMP/system.desktop" \
    SPOTIFY_SETUP_REPO='/a%b' bash "$SETUP" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "setup: refuses a % (an Exec field code)"
# A PATH with only what setup.sh needs, since the real spotify-launcher may be
# installed on the machine running the tests.
mkdir -p "$TMP/bare"
for c in bash dirname cat mkdir; do ln -sf "$(command -v "$c")" "$TMP/bare/$c"; done
fresh stock
out=$(PATH="$TMP/bare" HOME="$h" XDG_DATA_HOME="$h/data" SPOTIFY_DESKTOP_SRC="$TMP/system.desktop" \
    "$TMP/bare/bash" "$SETUP" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 0 "setup without spotify-launcher: exits 0"
assert_eq "$(entry)" "" "setup without spotify-launcher: writes nothing"
setup --bogus
assert_eq "$rc" 2 "setup: an unknown option exits 2"

test_summary "spotify"
