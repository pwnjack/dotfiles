#!/bin/bash
#
# Tests for scripts/updates/updates-plan.sh. Stubs replace checkupdates,
# pacman and the AUR helper, so the suite needs no network and no pending
# updates.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN="$TEST_DIR/../updates-plan.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=scripts/lib/assert.sh
. "$TEST_DIR/../../lib/assert.sh"

mkdir -p "$TMP/bin" "$TMP/cache" "$TMP/local" "$TMP/flatpak-system" "$TMP/data/flatpak"

# stub <name> <script body> — an executable on PATH.
stub() { printf '#!/bin/bash\n%s\n' "$2" > "$TMP/bin/$1"; chmod +x "$TMP/bin/$1"; }

stub checkupdates 'printf "%s\n" "mesa 1:26.2.1-1 -> 1:26.2.2-1" "linux-cachyos 7.2.8-2 -> 7.2.9-1"; exit 0'
# pacman: -Sup prints name size location; -Qqo names the owner of the modules dir.
stub pacman 'case "$1" in
  -Sup) printf "%s\n" "mesa 31457280 https://mirror/mesa-1:26.2.2-1-x86_64.pkg.tar.zst" \
                      "linux-cachyos 148478361 https://mirror/linux-cachyos-7.2.9-1-x86_64.pkg.tar.zst" \
                      "newdep 1048576 https://mirror/newdep-1-1-any.pkg.tar.zst" ;;
  -Qqo) [ "$2" = "'"$TMP"'/modules/7.2.8-2-cachyos" ] && echo linux-cachyos ;;
esac'
stub paru 'echo "spotblock-git 1.0-1 -> 1.1-1"; exit 0'
# flatpak: `list` names installed refs; `remote-ls --updates` names pending
# ones. FP_LIST / FP_UPDATES / FP_RC steer it; remote-ls leaves a probe file.
stub flatpak 'case "$1" in
  list) [ -n "${FP_LIST-}" ] && printf "%s\n" $FP_LIST ;;
  --installations) echo "'"$TMP"'/flatpak-system" ;;
  remote-ls) touch "'"$TMP"'/fp-ran"; [ -n "${FP_UPDATES-}" ] && printf "%s\n" $FP_UPDATES; exit "${FP_RC:-0}" ;;
esac'
echo 'paru -Syu' > "$TMP/aurhelper"

run() {
    PATH="$TMP/bin:$PATH" UPDATES_AURHELPER="$TMP/aurhelper" UPDATES_CACHE_DIR="$TMP/cache" \
        UPDATES_KERNEL=7.2.8-2-cachyos UPDATES_DB="$TMP/db" UPDATES_MODULES_DIR="$TMP/modules" \
        UPDATES_LOCK_TIMEOUT="${LOCK_T:-5}" UPDATES_STATE_DIR="$TMP/state" UPDATES_LOCAL_DB="$TMP/local" \
        XDG_DATA_HOME="$TMP/data" \
        bash "$PLAN" "$@"
}
# cached — the saved plan, as the card reads it; "exit <n>" when there is none.
cached() { local out; out=$(run --cached) && printf '%s' "$out" || echo "exit $?"; }

echo "updates-plan.sh"

out=$(run)
assert_json_field "$out" '.repo | length' 2 "two repo updates"
assert_json_field "$out" '.repo[0].name' mesa "names come from checkupdates"
assert_json_field "$out" '.repo[0].old' '1:26.2.1-1' "old version"
assert_json_field "$out" '.repo[0].new' '1:26.2.2-1' "new version"
assert_json_field "$out" '.repo[0].bytes' 31457280 "per-package size from -Sup"
assert_json_field "$out" '.bytes' $((31457280 + 148478361 + 1048576)) "bytes include new dependencies"
assert_json_field "$out" '.kernel' true "the running kernel's package is planned"
assert_json_field "$out" '.repo[1].kernel' true "and its row is tagged"
assert_json_field "$out" '.repo[0].kernel' false "other rows are not"
assert_json_field "$out" '.aur[0].name' spotblock-git "AUR updates from the derived helper"
assert_json_field "$out" '.aur[0].old' 1.0-1 "AUR old version"
assert_json_field "$out" '.aur[0].new' 1.1-1 "AUR new version"

assert_json_field "$out" '.flatpak' 0 "no Flatpak installs count as 0"
[ -e "$TMP/fp-ran" ] && fp=ran || fp=skipped
assert_eq "$fp" skipped "remote-ls is not run without installs"

out=$(FP_LIST="org.a.App" FP_UPDATES="org.a.App org.gnome.Platform" run)
assert_json_field "$out" '.flatpak' 2 "pending Flatpak refs are counted"

out=$(FP_LIST="org.a.App" FP_RC=1 run)
assert_json_field "$out" '.flatpak' 0 "a failing remote-ls counts as 0, not a failed plan"

out=$(UPDATES_FLATPAK=nosuchflatpak run)
assert_json_field "$out" '.flatpak' 0 "no flatpak binary counts as 0"
rm -f "$TMP/fp-ran"

touch "$TMP/cache/mesa-1:26.2.2-1-x86_64.pkg.tar.zst"
out=$(run)
assert_json_field "$out" '.repo[0].bytes' 0 "a package already in the cache downloads nothing"
rm "$TMP/cache/mesa-1:26.2.2-1-x86_64.pkg.tar.zst"

# fails <label> <stderr pattern> [status]: run must exit with status (default
# 1), print the reason, no stdout.
fails() {
    local err rc
    err=$(run 2>&1 >"$TMP/stdout"); rc=$?
    assert_eq "$rc" "${3:-1}" "$1: exit ${3:-1}"
    assert_eq "$([[ "$err" == *"$2"* ]] && echo yes || echo "no: $err")" yes "$1: reason on stderr"
    assert_eq "$(cat "$TMP/stdout")" "" "$1: no JSON on stdout"
}

stub checkupdates 'exit 1'
fails "checkupdates exit 1" "Could not sync package databases"

stub checkupdates 'exit 2'
mv "$TMP/bin/checkupdates" "$TMP/checkupdates.off"
UPDATES_REPO_CMD=nosuchcheckupdates fails "checkupdates missing" "not installed"
mv "$TMP/checkupdates.off" "$TMP/bin/checkupdates"

stub checkupdates 'echo "mesa 1-1 -> 2-1"; exit 0'
stub pacman 'exit 1'
fails "pacman -Sup failure" "pacman cannot resolve" 3

stub pacman 'case "$1" in
  -Sup) printf "%s\n" "mesa 100 https://m/mesa.pkg" "junk notanumber https://m/junk.pkg" ;;
esac'
out=$(run)
assert_json_field "$out" '.bytes' 100 "a non-numeric size line is skipped"

stub checkupdates 'exit 0'
( flock 9; sleep 4 ) 9>"$TMP/db.lock" &
holder=$!
until ! flock -n "$TMP/db.lock" true 2>/dev/null; do sleep 0.1; done
LOCK_T=1 fails "lock held" "still running"
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null

stub checkupdates 'exit 2'
stub pacman 'exit 0'
stub pacman 'exit 0'
out=$(run)
assert_json_field "$out" '.repo | length' 0 "checkupdates exit 2 means none, not failure"
assert_json_field "$out" '.kernel' false "nothing planned, no restart"

echo 'nosuchhelper -Syu' > "$TMP/aurhelper"
out=$(run)
assert_json_field "$out" '.aur | length' 0 "an uninstalled AUR helper gives no AUR rows"

echo "saved plan"
stub checkupdates 'touch "'"$TMP"'/checked"; echo "mesa 1-1 -> 2-1"; exit 0'
stub pacman 'case "$1" in -Sup) echo "mesa 100 https://m/mesa.pkg" ;; esac'
rm -rf "$TMP/state"
assert_eq "$(cached)" "exit 4" "no saved plan before the first check"
touch -d @1000 "$TMP/local"
out=$(run)
assert_json_field "$out" '.checkedAt | type' number "the plan says when it was checked"
assert_eq "$(cat "$TMP/state/plan.json")" "$out" "a printed plan is saved as printed"
rm -f "$TMP/checked"
assert_eq "$(cached)" "$out" "--cached prints the saved plan"
assert_eq "$([ -e "$TMP/checked" ] && echo ran || echo skipped)" skipped "--cached never runs the check"

touch -d @"$(jq .checkedAt <<< "$out")" "$TMP/local"
assert_eq "$(cached)" "exit 4" "packages changed in the second the check began: not usable"
touch -d @1000 "$TMP/local"
rmdir "$TMP/local"
assert_eq "$(cached)" "exit 4" "an unreadable local database: not usable"
mkdir "$TMP/local"; touch -d @1000 "$TMP/local"
echo '{"repo":[]}' > "$TMP/state/plan.json"
assert_eq "$(cached)" "exit 4" "a saved plan without checkedAt is not usable"

run >/dev/null
now=$(jq .checkedAt "$TMP/state/plan.json")
for marker in flatpak-system/.changed data/flatpak/.changed; do
    touch -d @"$now" "$TMP/$marker"
    assert_eq "$(cached)" "exit 4" "a Flatpak change since the check ($marker): not usable"
    touch -d @1000 "$TMP/$marker"
done
assert_eq "$(cached | jq -r '.repo[0].name')" mesa "older Flatpak changes leave it usable"

stub checkupdates 'exit 1'
run >/dev/null 2>&1
assert_eq "$(cached)" "$(cat "$TMP/state/plan.json")" "a check that cannot run keeps the saved plan"
assert_eq "$(cached | jq -r '.repo[0].name')" mesa "and it is the last good one"

stub checkupdates 'echo "mesa 1-1 -> 2-1"; exit 0'
stub pacman 'exit 1'
run >/dev/null 2>&1
assert_eq "$([ -e "$TMP/state/plan.json" ] && echo kept || echo removed)" removed \
    "an unresolvable upgrade removes the saved plan"

test_summary "updates-plan"
