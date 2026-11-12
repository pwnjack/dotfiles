#!/bin/bash
#
# Tests for the scripts under sddm/: update_sddm.sh, setup-sudo.sh,
# update_sddm_root.sh and watch_wallpaper.sh.
#
# Standalone, exit 1 on any failure. Every case runs against stubs on a
# throwaway PATH and fixture tree; nothing touches /usr/local/bin or /etc and
# nothing needs sudo. The doctor's check_sddm has its own tests in
# scripts/doctor/test/test-sddm.sh.
#
# The mutation seds below match shell source literally; nothing should expand.
# shellcheck disable=SC2016
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=scripts/lib/assert.sh
# shellcheck disable=SC1091
. "$REPO_DIR/scripts/lib/assert.sh"

make_fixture() { mktemp -d "$TMP/fixture.XXXXXXXX"; }

# --- updater rejects ambiguous or unsafe installed-helper paths -----------
sddm_script_fixture="$(make_fixture)"
mkdir -p "$sddm_script_fixture/sddm" "$sddm_script_fixture/bin" \
         "$sddm_script_fixture/host/bin"
cp "$REPO_DIR/sddm/update_sddm.sh" "$sddm_script_fixture/sddm/update_sddm.sh"
printf '#!/bin/bash\nexit 0\n' > "$sddm_script_fixture/host/bin/helper"
chmod +x "$sddm_script_fixture/host/bin/helper"

cat > "$sddm_script_fixture/bin/stat" <<'SDDM_STAT_EOF'
#!/bin/bash
if [[ "$2" == "%U:%G %a" ]]; then
    printf '%s\n' "${SDDM_TEST_STAT_NAMED:-root:root 755}"
else
    printf '%s\n' "${SDDM_TEST_STAT_NUMERIC:-0 755}"
fi
SDDM_STAT_EOF
cat > "$sddm_script_fixture/bin/sudo" <<'SDDM_SUDO_EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$SDDM_TEST_SUDO_LOG"
if [[ "$1" == "-n" && "$2" == "-l" ]]; then
    printf '%s\n' "${SDDM_TEST_SUDO_LISTING:-}"
elif [[ "$1" == "visudo" ]]; then
    cp "${@: -1}" "$SDDM_TEST_RULE_COPY"
fi
exit 0
SDDM_SUDO_EOF
chmod +x "$sddm_script_fixture/bin/stat" "$sddm_script_fixture/bin/sudo"
sddm_sudo_log="$sddm_script_fixture/sudo.log"
sddm_rule_copy="$sddm_script_fixture/generated-rule"

printf 'INSTALLED_HELPER="%s"\nINSTALLED_HELPER="%s"\n' \
    "$sddm_script_fixture/host/bin/helper" \
    "$sddm_script_fixture/host/bin/second" \
    > "$sddm_script_fixture/sddm/setup-sudo.sh"
: > "$sddm_sudo_log"
sddm_script_out=$(USER=fixture-user \
    PATH="$sddm_script_fixture/bin:$PATH" \
    SDDM_TEST_SUDO_LOG="$sddm_sudo_log" \
    bash "$sddm_script_fixture/sddm/update_sddm.sh" 2>&1)
sddm_script_status=$?
assert_eq "$sddm_script_status" "1" \
    "updater rejects duplicate INSTALLED_HELPER definitions"
assert_contains "$sddm_script_out" "cannot derive one installed SDDM helper" \
    "duplicate helper diagnostic explains the ambiguity"
assert_eq "$(cat "$sddm_sudo_log")" "" \
    "ambiguous updater path is rejected before sudo"

printf 'INSTALLED_HELPER="%s"\n' \
    "$sddm_script_fixture/host/bin/helper" \
    > "$sddm_script_fixture/sddm/setup-sudo.sh"
: > "$sddm_sudo_log"
sddm_script_out=$(USER=fixture-user \
    PATH="$sddm_script_fixture/bin:$PATH" \
    SDDM_TEST_STAT_NUMERIC="1000 755" \
    SDDM_TEST_SUDO_LOG="$sddm_sudo_log" \
    bash "$sddm_script_fixture/sddm/update_sddm.sh" 2>&1)
sddm_script_status=$?
assert_eq "$sddm_script_status" "1" \
    "updater rejects a user-owned installed helper"
assert_contains "$sddm_script_out" "helper is missing or unsafe" \
    "unsafe installed helper points back to setup-sudo.sh"
assert_eq "$(cat "$sddm_sudo_log")" "" \
    "unsafe updater path is rejected before both sudo branches"

: > "$sddm_sudo_log"
sddm_script_out=$(USER=fixture-user \
    PATH="$sddm_script_fixture/bin:$PATH" \
    SDDM_TEST_STAT_NUMERIC="0 755" \
    SDDM_TEST_SUDO_LOG="$sddm_sudo_log" \
    bash "$sddm_script_fixture/sddm/update_sddm.sh" 2>&1)
sddm_script_status=$?
assert_eq "$sddm_script_status" "0" \
    "safe installed helper reaches passwordless sudo"
assert_eq "$(cat "$sddm_sudo_log")" \
    "-n $sddm_script_fixture/host/bin/helper fixture-user" \
    "updater invokes exactly the helper and username pinned by sudoers"

# --- setup avoids prompts when current and pins new grants ----------------
sddm_setup_fixture="$(make_fixture)"
mkdir -p "$sddm_setup_fixture/sddm" "$sddm_setup_fixture/host/bin" \
         "$sddm_setup_fixture/host/sudoers"
cp "$REPO_DIR/sddm/setup-sudo.sh" "$sddm_setup_fixture/sddm/setup-sudo.sh"
cp "$REPO_DIR/sddm/update_sddm_root.sh" \
    "$sddm_setup_fixture/sddm/update_sddm_root.sh"
sddm_setup_helper="$sddm_setup_fixture/host/bin/helper"
sddm_setup_sudoers="$sddm_setup_fixture/host/sudoers/rule"
cp "$sddm_setup_fixture/sddm/update_sddm_root.sh" "$sddm_setup_helper"
sed -i \
    -e "s|^SUDOERS_FILE=.*|SUDOERS_FILE=\"$sddm_setup_sudoers\"|" \
    -e "s|^INSTALLED_HELPER=.*|INSTALLED_HELPER=\"$sddm_setup_helper\"|" \
    "$sddm_setup_fixture/sddm/setup-sudo.sh"

: > "$sddm_sudo_log"
sddm_current_listing=$(printf '%s\n%s\n%s' \
    "(root) NOPASSWD: $sddm_setup_helper fixture-user" \
    "(root) NOPASSWD: /usr/bin/true" \
    "(root) /tmp/Backgrounds/wallpaper.jpg")
sddm_script_out=$(USER=fixture-user \
    PATH="$sddm_script_fixture/bin:$PATH" \
    SDDM_TEST_STAT_NAMED="root:root 755" \
    SDDM_TEST_SUDO_LOG="$sddm_sudo_log" \
    SDDM_TEST_SUDO_LISTING="$sddm_current_listing" \
    SDDM_TEST_RULE_COPY="$sddm_rule_copy" \
    bash "$sddm_setup_fixture/sddm/setup-sudo.sh" 2>&1)
sddm_script_status=$?
assert_eq "$sddm_script_status" "0" \
    "fully configured setup completes without an install path"
assert_not_contains "$(cat "$sddm_sudo_log")" "visudo" \
    "current setup does not run visudo"
assert_not_contains "$(cat "$sddm_sudo_log")" "install" \
    "current setup does not reinstall privileged files"
assert_contains "$(cat "$sddm_sudo_log")" "-n -l" \
    "setup inspects grants with non-interactive sudo"
assert_not_contains "$sddm_script_out" "obsolete NOPASSWD rule" \
    "legacy detector does not span separate sudo-listing lines"

: > "$sddm_sudo_log"
sddm_script_out=$(USER=fixture-user \
    PATH="$sddm_script_fixture/bin:$PATH" \
    SDDM_TEST_STAT_NAMED="root:root 755" \
    SDDM_TEST_SUDO_LOG="$sddm_sudo_log" \
    SDDM_TEST_SUDO_LISTING="(ALL) NOPASSWD: ALL" \
    SDDM_TEST_RULE_COPY="$sddm_rule_copy" \
    bash "$sddm_setup_fixture/sddm/setup-sudo.sh" 2>&1)
sddm_script_status=$?
assert_eq "$sddm_script_status" "0" \
    "setup accepts an existing blanket NOPASSWD: ALL grant"
assert_not_contains "$(cat "$sddm_sudo_log")" "visudo" \
    "blanket grant does not force sudoers validation"
assert_not_contains "$(cat "$sddm_sudo_log")" "install" \
    "blanket grant does not reinstall privileged files"

: > "$sddm_sudo_log"
sddm_comma_listing="(root) NOPASSWD: /usr/bin/true, $sddm_setup_helper fixture-user, /usr/bin/false"
sddm_script_out=$(USER=fixture-user \
    PATH="$sddm_script_fixture/bin:$PATH" \
    SDDM_TEST_STAT_NAMED="root:root 755" \
    SDDM_TEST_SUDO_LOG="$sddm_sudo_log" \
    SDDM_TEST_SUDO_LISTING="$sddm_comma_listing" \
    SDDM_TEST_RULE_COPY="$sddm_rule_copy" \
    bash "$sddm_setup_fixture/sddm/setup-sudo.sh" 2>&1)
sddm_script_status=$?
assert_eq "$sddm_script_status" "0" \
    "setup accepts the helper within a comma-separated command list"
assert_not_contains "$(cat "$sddm_sudo_log")" "visudo" \
    "comma-separated helper grant does not force sudoers validation"
assert_not_contains "$(cat "$sddm_sudo_log")" "install" \
    "comma-separated helper grant does not reinstall privileged files"

: > "$sddm_sudo_log"
rm "$sddm_setup_helper"
sddm_script_out=$(USER=fixture-user \
    PATH="$sddm_script_fixture/bin:$PATH" \
    SDDM_TEST_STAT_NAMED="root:root 755" \
    SDDM_TEST_SUDO_LOG="$sddm_sudo_log" \
    SDDM_TEST_SUDO_LISTING="" \
    SDDM_TEST_RULE_COPY="$sddm_rule_copy" \
    bash "$sddm_setup_fixture/sddm/setup-sudo.sh" 2>&1)
sddm_script_status=$?
assert_eq "$sddm_script_status" "0" \
    "drifted setup validates and installs through mocked sudo"
assert_eq "$(cat "$sddm_rule_copy")" \
    "fixture-user ALL=(root) NOPASSWD: $sddm_setup_helper fixture-user" \
    "generated sudoers rule pins the invoking username argument"
sddm_setup_log="$(cat "$sddm_sudo_log")"
assert_contains "$sddm_setup_log" "visudo -c -f" \
    "drifted sudoers rule is validated"
assert_contains "$sddm_setup_log" "install -m 0755 -o root -g root" \
    "drifted helper uses root-owned mode-0755 installation"
assert_contains "$sddm_setup_log" "install -m 0440 -o root -g root" \
    "drifted sudoers file uses root-owned mode-0440 installation"

# --- watcher preserves automatic failures in the journal ------------------
sddm_watch_source="$(cat "$REPO_DIR/sddm/watch_wallpaper.sh")"
assert_contains "$sddm_watch_source" "2> >(logger -t sddm-wallpaper-sync)" \
    "watcher routes updater stderr to its stable journal tag"

# --- wallpaper discovery and decode run only after dropping privileges ----
# This is a source regression test, not a doctor finding. The doctor's cmp
# already reports an installed helper that differs from this tracked source;
# checking the installed copy for a particular implementation would add no
# independent live-system health signal. The fixture logs every runuser
# boundary, making removal of the drop around discovery, the ffmpeg lookup or
# the decode observable even when the root-side command would otherwise work.
sddm_decode_fixture="$(make_fixture)"
sddm_decode_home="$sddm_decode_fixture/home/fixture-user"
sddm_decode_bin="$sddm_decode_fixture/bin"
sddm_decode_themes="$sddm_decode_fixture/themes"
sddm_decode_theme="$sddm_decode_themes/fixture-theme"
sddm_decode_helper="$sddm_decode_fixture/update-helper"
sddm_decode_runuser_log="$sddm_decode_fixture/runuser.log"
sddm_decode_ffmpeg_log="$sddm_decode_fixture/ffmpeg.log"
sddm_decode_source="$sddm_decode_fixture/source.jpg"
sddm_decode_background="$sddm_decode_theme/Backgrounds/wallpaper.jpg"
sddm_decode_conf="$sddm_decode_fixture/sddm.conf"
sddm_decode_expected_boundaries="discovery
ffmpeg-check
decode"

mkdir -p "$sddm_decode_home/.config/options" \
         "$sddm_decode_home/.cache/awww/1" \
         "$sddm_decode_theme/Backgrounds" \
         "$sddm_decode_bin"
printf 'fixture-monitor\n' > "$sddm_decode_home/.config/options/mainmonitor"
# awww 0.12's real format: NUL-separated fields, no trailing newline. A helper
# that reads it without grep -a finds no path and never reaches the decode.
printf '\0crop:center\0Lanczos3\0%s' "$sddm_decode_source" > \
    "$sddm_decode_home/.cache/awww/1/fixture-monitor"
printf '[Theme]\nCurrent=fixture-theme\n' > "$sddm_decode_conf"
printf 'decodable\n' > "$sddm_decode_source"
printf 'original background\n' > "$sddm_decode_background"

cp "$REPO_DIR/sddm/update_sddm_root.sh" "$sddm_decode_helper"
sed -i \
    -e "s|^RUNUSER=.*|RUNUSER=\"$sddm_decode_bin/runuser\"|" \
    -e "s|^LOCK_FILE=.*|LOCK_FILE=\"$sddm_decode_bin/sddm-wallpaper.lock\"|" \
    -e "s|/usr/share/sddm/themes|$sddm_decode_themes|g" \
    -e "s|/etc/sddm.conf|$sddm_decode_conf|g" \
    "$sddm_decode_helper"

cat > "$sddm_decode_bin/getent" <<'SDDM_GETENT_EOF'
#!/bin/bash
if [[ "$1" == "passwd" && "$2" == "fixture-user" ]]; then
    printf 'fixture-user:x:1000:1000::%s:/bin/bash\n' "$SDDM_TEST_USER_HOME"
fi
SDDM_GETENT_EOF

cat > "$sddm_decode_bin/runuser" <<'SDDM_RUNUSER_EOF'
#!/bin/bash
if [[ "$1" != "-u" || "$2" != "fixture-user" || "$3" != "--" ]]; then
    exit 90
fi
shift 3

case "$1" in
    /bin/bash)
        if [[ "$3" == *'.cache/awww/'* ]]; then
            boundary=discovery
        elif [[ "$3" == *'command -v ffmpeg'* ]]; then
            boundary=ffmpeg-check
        else
            boundary=unknown-shell
        fi
        ;;
    ffmpeg) boundary=decode ;;
    *) boundary=unknown-command ;;
esac
printf '%s\n' "$boundary" >> "$SDDM_TEST_RUNUSER_LOG"
SDDM_TEST_UNPRIVILEGED=1 "$@"
SDDM_RUNUSER_EOF

cat > "$sddm_decode_bin/ffmpeg" <<'SDDM_FFMPEG_EOF'
#!/bin/bash
printf 'identity=%s argv=' "${SDDM_TEST_UNPRIVILEGED:-root}" >> "$SDDM_TEST_FFMPEG_LOG"
printf '<%s>' "$@" >> "$SDDM_TEST_FFMPEG_LOG"
printf '\n' >> "$SDDM_TEST_FFMPEG_LOG"
[[ "${SDDM_TEST_UNPRIVILEGED:-}" == "1" ]] || exit 91

input=""
single_frame=false
while [[ "$#" -gt 0 ]]; do
    if [[ "$1" == "-i" && "$#" -ge 2 ]]; then
        input="$2"
        shift 2
    elif [[ "$1" == "-frames:v" && "${2:-}" == "1" ]]; then
        single_frame=true
        shift 2
    else
        shift
    fi
done

case "$(/usr/bin/cat "$input" 2>/dev/null)" in
    decodable)
        printf 'converted jpeg\n'
        ;;
    multiframe)
        printf 'frame one\n'
        $single_frame || printf 'frame two\n'
        ;;
    empty-output)
        exit 0
        ;;
    signal)
        runuser_pid=$PPID
        helper_pid=$(ps -o ppid= -p "$runuser_pid" | tr -d ' ')
        kill -TERM "$helper_pid"
        sleep 0.1
        printf 'interrupted output\n'
        ;;
    *)
        exit 92
        ;;
esac
SDDM_FFMPEG_EOF

# The helper asks for owner and mode together; the fixture answers for its two
# directories (root-owned 0755 unless a test says otherwise) and defers the rest.
cat > "$sddm_decode_bin/stat" <<'SDDM_STAT_EOF'
#!/bin/bash
if [[ "$1" == "-c" && "$2" == "%u %a" && "$3" == "--" ]]; then
    case "$4" in
        */fixture-theme) printf '%s %s\n' "${SDDM_TEST_THEME_OWNER:-0}" "${SDDM_TEST_THEME_MODE:-755}" ;;
        */Backgrounds) printf '%s %s\n' "${SDDM_TEST_BACKGROUNDS_OWNER:-0}" "${SDDM_TEST_BACKGROUNDS_MODE:-755}" ;;
        *) /usr/bin/stat "$@" ;;
    esac
else
    /usr/bin/stat "$@"
fi
SDDM_STAT_EOF
chmod +x "$sddm_decode_bin/getent" "$sddm_decode_bin/runuser" \
    "$sddm_decode_bin/ffmpeg" "$sddm_decode_bin/stat" "$sddm_decode_helper"

sddm_decode_run() {
    : > "$sddm_decode_runuser_log"
    : > "$sddm_decode_ffmpeg_log"
    sddm_decode_out=$(SDDM_TEST_USER_HOME="$sddm_decode_home" \
        SDDM_TEST_RUNUSER_LOG="$sddm_decode_runuser_log" \
        SDDM_TEST_FFMPEG_LOG="$sddm_decode_ffmpeg_log" \
        SDDM_TEST_THEME_OWNER="${SDDM_TEST_THEME_OWNER:-0}" \
        SDDM_TEST_BACKGROUNDS_OWNER="${SDDM_TEST_BACKGROUNDS_OWNER:-0}" \
        SDDM_TEST_BACKGROUNDS_MODE="${SDDM_TEST_BACKGROUNDS_MODE:-755}" \
        PATH="$sddm_decode_bin:/usr/bin:/bin" \
        bash "${1:-$sddm_decode_helper}" fixture-user 2>&1)
    sddm_decode_status=$?
}

sddm_decode_run
assert_eq "$sddm_decode_status" "0" \
    "root helper succeeds when ffmpeg runs through runuser"
assert_eq "$sddm_decode_out" "" \
    "successful root helper remains quiet"
assert_eq "$(cat "$sddm_decode_runuser_log")" "$sddm_decode_expected_boundaries" \
    "discovery, ffmpeg lookup and decode cross the expected privilege boundaries"
assert_contains "$(cat "$sddm_decode_ffmpeg_log")" "identity=1" \
    "ffmpeg observes the unprivileged execution boundary"
assert_eq "$(cat "$sddm_decode_background")" "converted jpeg" \
    "successful decode atomically replaces the greeter background"
assert_eq "$(stat -c %a -- "$sddm_decode_background")" "644" \
    "installed greeter background is explicitly world-readable"

# Animated inputs must render exactly one JPEG frame rather than concatenating
# an unbounded MJPEG stream into the destination.
printf 'multiframe\n' > "$sddm_decode_source"
printf 'original background\n' > "$sddm_decode_background"
sddm_decode_run
assert_eq "$sddm_decode_status" "0" \
    "multi-frame input converts successfully"
assert_eq "$(cat "$sddm_decode_background")" "frame one" \
    "multi-frame input installs exactly one output frame"
assert_contains "$(cat "$sddm_decode_ffmpeg_log")" "<-frames:v><1>" \
    "decode explicitly requests one frame from ffmpeg"

# A successful ffmpeg exit with no bytes is not a successful conversion and
# must not replace the last known-good background.
printf 'empty-output\n' > "$sddm_decode_source"
printf 'original background\n' > "$sddm_decode_background"
sddm_decode_run
assert_eq "$sddm_decode_status" "1" \
    "zero-length decode output preserves the failure exit contract"
assert_eq "$(cat "$sddm_decode_background")" "original background" \
    "zero-length decode output does not replace the previous background"

# A bad source must remove only the temporary output, never truncate the
# previously installed background.
printf 'undecodable\n' > "$sddm_decode_source"
printf 'original background\n' > "$sddm_decode_background"
sddm_decode_run
assert_eq "$sddm_decode_status" "1" \
    "failed decode preserves the helper's failure exit contract"
assert_eq "$(cat "$sddm_decode_background")" "original background" \
    "failed decode leaves the previous greeter background intact"
shopt -s nullglob
sddm_decode_temporaries=("$sddm_decode_theme/Backgrounds"/.wallpaper.jpg.*)
shopt -u nullglob
assert_eq "${#sddm_decode_temporaries[@]}" "0" \
    "failed decode removes its root-created temporary output"

# A termination after mktemp must run the EXIT cleanup before the helper dies.
printf 'signal\n' > "$sddm_decode_source"
printf 'original background\n' > "$sddm_decode_background"
sddm_decode_run
assert_eq "$sddm_decode_status" "143" \
    "termination during decode preserves the signal exit status"
shopt -s nullglob
sddm_decode_temporaries=("$sddm_decode_theme/Backgrounds"/.wallpaper.jpg.*)
shopt -u nullglob
assert_eq "${#sddm_decode_temporaries[@]}" "0" \
    "termination between mktemp and rename leaves no temporary behind"
assert_eq "$(cat "$sddm_decode_background")" "original background" \
    "terminated decode leaves the previous background intact"

# A root-owned but world-writable Backgrounds directory lets another user swap
# the temporary file for a symlink before root writes: refused the same way.
printf 'decodable\n' > "$sddm_decode_source"
printf 'original background\n' > "$sddm_decode_background"
SDDM_TEST_BACKGROUNDS_MODE=777 sddm_decode_run
assert_eq "$sddm_decode_status" "1" "a world-writable Backgrounds directory is refused"
assert_contains "$sddm_decode_out" "writable by others" "unsafe Backgrounds mode reports the violated invariant"
assert_eq "$(cat "$sddm_decode_background")" "original background" "unsafe Backgrounds mode cannot replace the background"

# The helper enforces the root-owned destination invariant itself rather than
# relying on the report-only doctor check.
printf 'decodable\n' > "$sddm_decode_source"
printf 'original background\n' > "$sddm_decode_background"
SDDM_TEST_THEME_OWNER=1000 sddm_decode_run
assert_eq "$sddm_decode_status" "1" \
    "non-root-owned theme directory is refused"
assert_contains "$sddm_decode_out" "resolved theme directory is not root-owned" \
    "unsafe theme ownership reports the violated invariant"
assert_eq "$(cat "$sddm_decode_runuser_log")" "discovery
ffmpeg-check" \
    "unsafe theme is refused before the decode boundary"
assert_eq "$(cat "$sddm_decode_background")" "original background" \
    "unsafe theme ownership cannot replace the background"

printf 'original background\n' > "$sddm_decode_background"
SDDM_TEST_BACKGROUNDS_OWNER=1000 sddm_decode_run
assert_eq "$sddm_decode_status" "1" \
    "non-root-owned Backgrounds directory is refused"
assert_contains "$sddm_decode_out" \
    "resolved Backgrounds directory is not root-owned" \
    "unsafe Backgrounds ownership reports the violated invariant"
assert_eq "$(cat "$sddm_decode_runuser_log")" "discovery
ffmpeg-check" \
    "unsafe Backgrounds directory is refused before the decode boundary"
assert_eq "$(cat "$sddm_decode_background")" "original background" \
    "unsafe Backgrounds ownership cannot replace the background"

# Prove the sequence guard is mutation-sensitive at every remaining boundary.
# Discovery includes the home-directory check, monitor read, cache lookup,
# cache parse, both file guards and symlink fallback in one child shell.
printf 'decodable\n' > "$sddm_decode_source"
printf 'original background\n' > "$sddm_decode_background"
sddm_discovery_unsafe="$sddm_decode_fixture/update-helper-root-discovery"
cp "$sddm_decode_helper" "$sddm_discovery_unsafe"
sed -i 's/wallpaper=$("$RUNUSER" -u "$TARGET_USER" -- /wallpaper=$(/' \
    "$sddm_discovery_unsafe"
sddm_decode_run "$sddm_discovery_unsafe"
assert_eq "$sddm_decode_status" "0" \
    "discovery mutation remains executable instead of failing trivially"
assert_eq "$(cat "$sddm_decode_runuser_log")" "ffmpeg-check
decode" \
    "removing discovery's privilege drop is visible to the sequence guard"

sddm_lookup_unsafe="$sddm_decode_fixture/update-helper-root-ffmpeg-lookup"
cp "$sddm_decode_helper" "$sddm_lookup_unsafe"
sed -i \
    -e '/^if ! "$RUNUSER" -u "$TARGET_USER" -- \\$/d' \
    -e "s|^     /bin/bash -c 'command -v ffmpeg >/dev/null'; then|if ! command -v ffmpeg >/dev/null; then|" \
    "$sddm_lookup_unsafe"
printf 'original background\n' > "$sddm_decode_background"
sddm_decode_run "$sddm_lookup_unsafe"
assert_eq "$sddm_decode_status" "0" \
    "ffmpeg-lookup mutation remains executable instead of failing trivially"
assert_eq "$(cat "$sddm_decode_runuser_log")" "discovery
decode" \
    "removing ffmpeg lookup's privilege drop is visible to the sequence guard"

# The decode mutation additionally reaches the mock ffmpeg as root and is
# rejected at execution time.
sddm_decode_unsafe="$sddm_decode_fixture/update-helper-without-drop"
cp "$sddm_decode_helper" "$sddm_decode_unsafe"
sed -i 's/if "$RUNUSER" -u "$TARGET_USER" -- \\/if \\/' \
    "$sddm_decode_unsafe"
printf 'original background\n' > "$sddm_decode_background"
sddm_decode_run "$sddm_decode_unsafe"
assert_eq "$sddm_decode_status" "1" \
    "regression guard rejects a helper with the ffmpeg privilege drop removed"
assert_contains "$(cat "$sddm_decode_ffmpeg_log")" "identity=root" \
    "mutated helper demonstrates that direct ffmpeg would run as root"
assert_eq "$(cat "$sddm_decode_background")" "original background" \
    "rejected root-side decode cannot replace the prior background"

# Missing runuser is a hard failure; there is deliberately no root fallback.
rm "$sddm_decode_bin/runuser"
sddm_decode_run
assert_eq "$sddm_decode_status" "1" \
    "missing runuser exits non-zero"
assert_contains "$sddm_decode_out" \
    "runuser is required to decode the SDDM wallpaper without root privileges" \
    "missing runuser reports the security requirement clearly"
assert_eq "$(cat "$sddm_decode_ffmpeg_log")" "" \
    "missing runuser never falls back to root-side ffmpeg"


test_summary sddm
