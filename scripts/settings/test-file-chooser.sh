#!/bin/bash
#
# FileChooser registration tests with a fake HOME, XDG directories and bus.
# PATH contains only test stubs and utilities, so no real Strata or bus runs.

set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/file-chooser.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=scripts/lib/assert.sh disable=SC1091
. "$TEST_DIR/../lib/assert.sh"

mkdir -p "$TMP/bin" "$TMP/config/options" "$TMP/data" "$TMP/home"
for cmd in bash readlink mkdir cmp grep rm mktemp mv id; do
    ln -s "$(command -v "$cmd")" "$TMP/bin/$cmd"
done
# Model safe shared ancestors for these fixtures: /tmp is world-writable,
# and a sandbox can give / a synthetic owner. Components inside TMP retain
# real metadata. Separate tests restore /tmp's mode and set a foreign owner.
cat > "$TMP/bin/stat" <<'STUB_STAT'
#!/bin/bash
if [ "${!#}" = / ]; then
    printf '%s 755\n' "${ROOT_OWNER:-0}"
elif [ "${!#}" = /tmp ] && [ "${UNSAFE_TMP:-0}" = 0 ]; then
    printf '0 755\n'
else
    exec "$REAL_STAT" "$@"
fi
STUB_STAT
chmod +x "$TMP/bin/stat"
export REAL_STAT
REAL_STAT=$(command -v stat)
for cmd in busctl systemctl; do
    # shellcheck disable=SC2016  # Stub variables expand when the stub runs.
    printf '#!/bin/sh\necho "%s $*" >> "$CALLS"\nexit "${STUB_STATUS:-0}"\n' "$cmd" > "$TMP/bin/$cmd"
    chmod +x "$TMP/bin/$cmd"
done
# shellcheck disable=SC2016  # Stub variables expand when the stub runs.
printf '#!/bin/sh\necho "strata $*" >> "$CALLS"\nexit "${STUB_STATUS:-0}"\n' > "$TMP/strata-real"
chmod +x "$TMP/strata-real"
ln -s "$TMP/strata-real" "$TMP/bin/strata"

portal="$TMP/data/xdg-desktop-portal/portals/strata.portal"
service="$TMP/data/dbus-1/services/org.freedesktop.impl.portal.desktop.strata.service"
name=org.freedesktop.impl.portal.desktop.strata
run() {
    printf '%s\n' "$1" > "$TMP/config/options/filemanager"
    run_script
}
run_script() {
    : > "$TMP/calls"
    PATH="$TMP/bin" HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config" XDG_DATA_HOME="$TMP/data" \
        CALLS="$TMP/calls" bash "$SCRIPT"
}
assert_absent() {
    assert_eq "$([ -e "$1" ] && echo present || echo absent)" absent "$2"
}
assert_changed() {
    assert_eq "$(grep -c 'ReloadConfig' "$TMP/calls")" 1 "$1 reloads the bus once"
    assert_eq "$(grep -c 'systemctl --user try-restart xdg-desktop-portal.service' "$TMP/calls")" 1 \
        "$1 tries to restart the frontend once"
}

run '  strata --new-window'
assert_eq "$?" 0 "install exits 0"
assert_eq "$(cat "$portal" 2>/dev/null)" "[portal]
DBusName=$name
Interfaces=org.freedesktop.impl.portal.FileChooser;" "installs the portal descriptor"
assert_eq "$(cat "$service" 2>/dev/null)" "[D-BUS Service]
Name=$name
Exec=$TMP/strata-real --portal" "Exec uses the canonical path rather than the PATH symlink"
assert_contains "$(cat "$TMP/calls")" 'strata --dismiss-portal-prompt' "dismisses Strata's in-app portal prompt"
assert_changed install

portal_stamp=$(stat -c '%y' "$portal")
service_stamp=$(stat -c '%y' "$service")
run strata
assert_eq "$(stat -c '%y' "$portal")" "$portal_stamp" "rerun leaves portal mtime unchanged"
assert_eq "$(stat -c '%y' "$service")" "$service_stamp" "rerun leaves service mtime unchanged"
assert_not_contains "$(cat "$TMP/calls")" busctl "a second run does not reload the bus"
assert_not_contains "$(cat "$TMP/calls")" systemctl "a second run does not restart the frontend"

run "$TMP/bin/strata --new-window"
assert_contains "$(cat "$service")" "Exec=$TMP/strata-real --portal" "a full-path option selects Strata"
assert_not_contains "$(cat "$TMP/calls")" busctl "a full-path rerun does not reload the bus"
ln -s "$TMP/strata-real" "$TMP/bin/alias-fm"
run alias-fm
assert_contains "$(cat "$service")" "Exec=$TMP/strata-real --portal" "a canonical alias selects Strata"

# Even matching content behind a target symlink must be replaced in place.
cp "$portal" "$TMP/foreign-portal"
cp "$service" "$TMP/foreign-service"
rm "$portal" "$service"
ln -s "$TMP/foreign-portal" "$portal"
ln -s "$TMP/foreign-service" "$service"
run strata
assert_eq "$([ -L "$portal" ] && echo link || echo file)" file "portal symlink is replaced"
assert_eq "$([ -L "$service" ] && echo link || echo file)" file "service symlink is replaced"
assert_changed 'symlink replacement'
# Changed content must likewise never be written into an unrelated file.
printf 'foreign portal\n' > "$TMP/foreign-portal"
printf 'foreign service\n' > "$TMP/foreign-service"
rm "$portal" "$service"
ln -s "$TMP/foreign-portal" "$portal"
ln -s "$TMP/foreign-service" "$service"
run strata
assert_eq "$(cat "$TMP/foreign-portal")" 'foreign portal' "portal symlink referent is untouched"
assert_eq "$(cat "$TMP/foreign-service")" 'foreign service' "service symlink referent is untouched"
assert_eq "$([ -L "$portal" ] && echo link || echo file)" file "changed portal symlink is replaced"
assert_eq "$([ -L "$service" ] && echo link || echo file)" file "changed service symlink is replaced"

run thunar
assert_contains "$(cat "$TMP/calls")" 'strata --dismiss-portal-prompt' "dismisses prompt with Thunar selected"
assert_absent "$portal" "switching to Thunar removes our portal descriptor"
assert_absent "$service" "switching to Thunar removes our service"
assert_changed removal
run thunar
assert_eq "$(cat "$TMP/calls")" 'strata --dismiss-portal-prompt' "another removal only dismisses the prompt"

printf '[portal]\nDBusName=org.example.Foreign\n' > "$portal"
printf '[D-BUS Service]\nName=org.example.Foreign\nExec=/opt/foreign\n' > "$service"
run thunar
assert_contains "$(cat "$portal")" 'org.example.Foreign' "a foreign portal survives"
assert_contains "$(cat "$service")" '/opt/foreign' "a foreign service survives"
assert_eq "$(cat "$TMP/calls")" 'strata --dismiss-portal-prompt' "foreign files only cause prompt dismissal"
rm -f "$portal" "$service"

# Check each disallowed character after canonicalisation, not just on PATH.
for bad in 'with space' "with'quote" 'with"quote' 'with\backslash'; do
    mkdir -p "$TMP/$bad"
    cp "$TMP/strata-real" "$TMP/$bad/strata"
    ln -sf "$TMP/$bad/strata" "$TMP/bin/strata"
    run strata
    assert_absent "$portal" "unsafe path ($bad) cannot install a portal"
    assert_absent "$service" "unsafe path ($bad) cannot install a service"
    assert_eq "$(cat "$TMP/calls")" '' "unsafe path ($bad) runs no probes"
done

# Refuse writable canonical directories and the executable itself, including
# an unsafe shared ancestor; no prompt dismissal may run through such a path.
mkdir -p "$TMP/writable"
cp "$TMP/strata-real" "$TMP/writable/strata"
ln -sf "$TMP/writable/strata" "$TMP/bin/strata"
for mode in 775 757; do
    chmod "$mode" "$TMP/writable"
    run strata
    assert_absent "$portal" "directory mode $mode refuses portal registration"
    assert_absent "$service" "directory mode $mode refuses service registration"
    assert_eq "$(cat "$TMP/calls")" '' "directory mode $mode runs no probes"
done
chmod 755 "$TMP/writable"
chmod 775 "$TMP/writable/strata"
run strata
assert_absent "$service" "group-writable executable is refused"
assert_eq "$(cat "$TMP/calls")" '' "group-writable executable runs no probes"
ln -sf "$TMP/strata-real" "$TMP/bin/strata"
UNSAFE_TMP=1 run strata
assert_absent "$service" "world-writable ancestor is refused"
assert_eq "$(cat "$TMP/calls")" '' "world-writable ancestor runs no probes"
ROOT_OWNER=65534 run strata
assert_absent "$service" "ancestor owned by another user is refused"
assert_eq "$(cat "$TMP/calls")" '' "foreign-owned ancestor runs no probes"

ln -sf "$TMP/strata-real" "$TMP/bin/strata"
run strata
rm -f "$TMP/bin/strata"
run strata
assert_absent "$portal" "Strata disappearing removes our portal"
assert_absent "$service" "Strata disappearing removes our service"
assert_changed 'missing Strata'
run strata
assert_eq "$?" 0 "missing Strata exits 0"
assert_absent "$portal" "missing Strata writes no portal"
assert_absent "$service" "missing Strata writes no service"
assert_eq "$(cat "$TMP/calls")" '' "missing Strata with no registration runs no probes"

ln -s "$TMP/strata-real" "$TMP/bin/strata"
rm -f "$TMP/config/options/filemanager"
run_script
assert_contains "$(cat "$service")" "Exec=$TMP/strata-real --portal" "a missing preference defaults to Strata"

# Optional probes can be missing or fail without failing the registration.
run thunar
STUB_STATUS=1 run strata
assert_eq "$?" 0 "failing bus, frontend and Strata probes still exit 0"
assert_changed 'failed probes'
run thunar
rm -f "$TMP/bin/busctl" "$TMP/bin/systemctl"
STUB_STATUS=1 run strata
assert_eq "$?" 0 "missing bus tools and a failing Strata probe still exit 0"
assert_contains "$(cat "$service")" "Exec=$TMP/strata-real --portal" "registration works without bus tools"
run thunar
assert_absent "$service" "removal works without bus tools"

test_summary file-chooser
