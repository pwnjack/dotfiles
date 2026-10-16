# Tests for scripts/doctor/checks/references.sh — sourced by run-tests.sh
#
# Sourced fragment, never executed directly, so it carries no shebang; the
# directive below tells shellcheck which shell to assume (SC2148).
# shellcheck shell=bash
#
# Checks are run ONCE, redirected to a file under $DOCTOR_TEST_TMP, and the
# output is read back. `out="$(check_x)"` would run the check in a subshell and
# discard its severity counters, forcing a second run to observe them — so the
# asserted text and the asserted counts would come from different executions.
#
# Every variable here is prefixed ref_ : test files share one shell.

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/references.sh"

# Assigned throughout this file but read only by the check sourced above — a
# cross-file use that SC2034 cannot see. Declare them external.
export DOCTOR_ROOT DOCTOR_CACHE

ref_out_file="$DOCTOR_TEST_TMP/references.out"

# =====================================================================
# A repo containing every reference state the check classifies.
# =====================================================================
ref_fixture="$(make_fixture)"

mkdir -p "$ref_fixture/hypr/config/spaced dir" \
         "$ref_fixture/scripts/doctor/test" \
         "$ref_fixture/scripts/doctor/checks" \
         "$ref_fixture/docs"

# --- Hyprland source chains -------------------------------------------------
# Heredocs are quoted so $HOME and $VARIABLE reach the fixture literally.
cat > "$ref_fixture/hypr/hyprland.conf" <<'EOF'
# main manifest
source = config/good.conf
source = config/missing.conf
source = config/inline.conf     # trailing comment must not become part of the path
source = config/spaced dir/there.conf
source = config/spaced dir/gone.conf
source = $VARIABLE/expanded.conf
source = config/*.conf
source = ~/.config/hypr/config/good.conf
source = /etc/hypr/absolute.conf
EOF

# Sources are resolved against the sourcing file's own directory, not against a
# hardcoded hypr/. This file proves the base is derived, not assumed.
cat > "$ref_fixture/hypr/hyprlock.conf" <<'EOF'
source = config/lock-missing.conf
EOF

# A conf at the top of the tree: its base directory is empty, so a naive
# "$root/$base/$target" would build a path containing a doubled slash.
cat > "$ref_fixture/top.conf" <<'EOF'
source = toplevel-target.conf
EOF

echo "colors" > "$ref_fixture/hypr/config/good.conf"
echo "inline" > "$ref_fixture/hypr/config/inline.conf"
echo "spaced" > "$ref_fixture/hypr/config/spaced dir/there.conf"

# --- Hyprland Lua module chain ----------------------------------------------
cat > "$ref_fixture/hypr/hyprland.lua" <<'EOF'
require("config.good")
require("config.missing_lua")
EOF
echo 'return {}' > "$ref_fixture/hypr/config/good.lua"

# --- literal ~/.config references -------------------------------------------
# docs/ and *.md cite illustrative paths that intentionally do not exist.
cat > "$ref_fixture/docs/plan.md" <<'EOF'
Illustrative: $HOME/.config/docs-md/never-exists
EOF
cat > "$ref_fixture/docs/notes.txt" <<'EOF'
Illustrative: $HOME/.config/docs-txt/never-exists
EOF
cat > "$ref_fixture/NOTES.md" <<'EOF'
Illustrative: ~/.config/md-only/never-exists
EOF

# The doctor's own tree. Its fixtures are built out of paths chosen for not
# existing, and its modules name example paths in prose, so scanning it makes
# the check's loudest finding itself.
cat > "$ref_fixture/scripts/doctor/test/test-example.sh" <<'EOF'
p="$HOME/.config/doctor-fixture/never-exists"
EOF
cat > "$ref_fixture/scripts/doctor/checks/example.sh" <<'EOF'
# A module comment citing ~/.config/doctor-prose/never-exists as an example.
EOF
cat > "$ref_fixture/scripts/doctor/test/fixture-example.conf" <<'EOF'
source = doctor-fixture-target.conf
EOF

cat > "$ref_fixture/scripts/broken.sh" <<'EOF'
exec "$HOME/.config/gone/missing.sh"
EOF

# The referencing file's name is interpolated into a fix hint, so it needs a
# space in it to prove the hint is shell-quoted.
cat > "$ref_fixture/has space.sh" <<'EOF'
exec "$HOME/.config/gone/missing2.sh"
EOF

# Paths that are still templates or globs at rest: nothing on disk can be
# expected to match them, so they must be skipped rather than reported.
cat > "$ref_fixture/scripts/dynamic.sh" <<'EOF'
theme="$HOME/.config/themes/$NAME/x.rasi"
all=(~/.config/themes/*.rasi)
one=~/.config/themes/?.rasi
set=~/.config/themes/[ab].rasi
EOF

# A reference used as a parameter-expansion default is followed by the
# expansion's own closing brace, which is not part of the path. A braced
# variable inside the path is, and keeps the path unresolvable.
cat > "$ref_fixture/scripts/defaults.sh" <<'EOF'
p="${PRESENT_OVERRIDE:-$HOME/.config/present.sh}"
# Overridable, e.g. ${PRESENT_OVERRIDE:-~/.config/present.sh}
g="${GONE_OVERRIDE:-$HOME/.config/gone/defaulted.sh}"
t="$HOME/.config/templated/${id}/x"
EOF

# The prefix strip must remove only the LEADING ~/.config/, never the last one.
cat > "$ref_fixture/nested.sh" <<'EOF'
p="$HOME/.config/scripts/x/.config/y"
EOF

cat > "$ref_fixture/present.sh" <<'EOF'
p="$HOME/.config/present.sh"
EOF

# --- a tracked symlink whose content is generated outside the repo ----------
# waypaper rewrites its own config in ~/.cache; a dangling reference inside it
# is not something an edit to this repo could fix.
ref_generated="$DOCTOR_TEST_TMP/ref-generated-content"
cat > "$ref_generated" <<'EOF'
stylesheet = ~/.config/generated/never-exists.css
EOF
ln -s "$ref_generated" "$ref_fixture/generated.ini"

git -C "$ref_fixture" add -A
git -C "$ref_fixture" commit -qm "fixture"

ref_cache_empty="$DOCTOR_TEST_TMP/ref-cache-empty"
mkdir -p "$ref_cache_empty"

DOCTOR_ROOT="$ref_fixture"
DOCTOR_CACHE="$ref_cache_empty"
doctor_reset
check_references > "$ref_out_file" 2>&1
ref_out="$(<"$ref_out_file")"

# --- source chains ----------------------------------------------------------
assert_contains "$ref_out" "hypr/hyprland.conf sources config/missing.conf" \
    "missing source target is reported"
# Hyprland fails the line outright and the whole module never loads, so this is
# the one reference kind that genuinely breaks the session.
ref_source_line="$(grep -F 'sources config/missing.conf' "$ref_out_file")"
assert_contains "$ref_source_line" "ERROR" "missing source target is ERROR severity"
assert_contains "$ref_out" "hypr/hyprlock.conf sources config/lock-missing.conf" \
    "source target is resolved against the sourcing file's own directory"
assert_not_contains "$ref_out" "config/good.conf, which does not exist" \
    "resolvable source target produces no finding"
assert_not_contains "$ref_out" "config/inline.conf, which does not exist" \
    "inline comment is stripped off the source target"
assert_not_contains "$ref_out" "trailing comment" \
    "no finding quotes the comment text back at the user"
assert_not_contains "$ref_out" "spaced dir/there.conf, which does not exist" \
    "source target containing a space still resolves"
assert_contains "$ref_out" "spaced dir/gone.conf" \
    "missing source target containing a space is reported"

# Neither a template nor a glob names a single file, so neither can be checked.
assert_not_contains "$ref_out" "expanded.conf" \
    "source target with an unexpanded variable is skipped"
assert_not_contains "$ref_out" "config/*.conf" \
    "globbed source target is skipped"
assert_not_contains "$ref_out" "absolute.conf" \
    "source target outside the tree under test is skipped"

assert_contains "$ref_out" "hypr/hyprland.lua requires config.missing_lua" \
    "missing Lua module is reported"
ref_require_line="$(grep -F 'requires config.missing_lua' "$ref_out_file")"
assert_contains "$ref_require_line" "ERROR" "missing Lua module is ERROR severity"
assert_not_contains "$ref_out" "requires config.good" \
    "resolvable Lua module produces no finding"

# --- literal ~/.config references -------------------------------------------
assert_contains "$ref_out" "scripts/broken.sh references ~/.config/gone/missing.sh" \
    "missing literal \$HOME/.config path is reported"
assert_not_contains "$ref_out" "present.sh, which does not exist" \
    "literal path that exists produces no finding"

# A script pointing at a missing file breaks that one feature when invoked; the
# session still comes up. ERROR is reserved for what stops the session, or the
# exit code stops meaning anything. Severity is asserted on the finding's own
# line — the whole-output "contains ERROR" form cannot tell which finding it
# came from once the check emits more than one severity.
ref_literal_line="$(grep -F 'scripts/broken.sh references' "$ref_out_file")"
assert_contains "$ref_literal_line" "WARN" "missing literal path is WARN severity"
assert_not_contains "$ref_literal_line" "ERROR" "missing literal path is not an ERROR"

# docs/ and *.md hold illustrative paths; reporting them would bury the real
# findings under the contents of every plan ever written.
assert_not_contains "$ref_out" "docs-md" "a .md file under docs/ is not scanned"
assert_not_contains "$ref_out" "docs-txt" "a non-md file under docs/ is not scanned"
assert_not_contains "$ref_out" "md-only" "a .md file outside docs/ is not scanned"

# Same rule, applied to the doctor's own tree: its fixtures are made of paths
# picked for not existing, so scanning it makes the check report on itself.
assert_not_contains "$ref_out" "doctor-fixture/never-exists" \
    "a test fixture under scripts/doctor/ is not scanned"
assert_not_contains "$ref_out" "doctor-prose" \
    "an example path in a check module's own comments is not scanned"
assert_not_contains "$ref_out" "doctor-fixture-target.conf" \
    "a fixture .conf under scripts/doctor/ is not walked for source lines"

assert_not_contains "$ref_out" "themes" \
    "paths holding a variable or a glob are skipped, not reported"

assert_not_contains "$ref_out" "present.sh}" \
    "a parameter-expansion default's closing brace is not part of the path"
assert_contains "$ref_out" "defaults.sh references ~/.config/gone/defaulted.sh," \
    "a missing path used as a default is reported without the brace"
assert_not_contains "$ref_out" "templated" \
    "a braced variable inside a path keeps it unresolvable"

# The strip must be anchored to the front. A longest-match strip would turn
# scripts/x/.config/y into y and send the reader to the wrong file.
assert_contains "$ref_out" "nested.sh references ~/.config/scripts/x/.config/y" \
    "only the leading ~/.config/ is stripped"
assert_not_contains "$ref_out" "references ~/.config/y," \
    "a later /.config/ in the path is not mistaken for the prefix"

# --- generated content ------------------------------------------------------
assert_not_contains "$ref_out" "generated/never-exists.css" \
    "content of a tracked symlink is not scanned"

# --- palette cache ----------------------------------------------------------
assert_contains "$ref_out" "$ref_cache_empty/wal/colors-hyprland.conf" \
    "missing Hyprlock palette cache is reported"
assert_contains "$ref_out" "$ref_cache_empty/wal/colors-hyprland.lua" \
    "missing Hyprland Lua palette cache is reported"
assert_contains "$ref_out" "palette cache missing: $ref_cache_empty/wal/colors" \
    "missing ANSI palette cache is reported"
assert_contains "$ref_out" "palette cache missing: $ref_cache_empty/wal/roles" \
    "missing semantic-role cache is reported"
for ref_name in colors roles colors-hyprland.conf colors-hyprland.lua; do
    ref_palette_line="$(grep -F "palette cache missing: $ref_cache_empty/wal/$ref_name" "$ref_out_file" | head -n1)"
    case "$ref_name" in
        colors|roles)
            assert_contains "$ref_palette_line" "WARN" "missing $ref_name uses fallback and is WARN severity"
            assert_not_contains "$ref_palette_line" "ERROR" "missing $ref_name is not an ERROR"
            ;;
        *) assert_contains "$ref_palette_line" "ERROR" "missing $ref_name leaves a dangling link and is ERROR severity" ;;
    esac
done

# --- tallies ----------------------------------------------------------------
# Only what stops the session: 4 source targets, 1 Lua module, 2 Hyprland outputs.
assert_eq "$DOCTOR_ERRORS" "7" "session-breaking references counted as errors"
# 4 literal references and 2 fallback palette inputs.
assert_eq "$DOCTOR_WARNINGS" "6" "degraded-feature references counted as warnings"
assert_eq "$DOCTOR_NOTICES" "0" "nothing here is a notice"

# --- every fix hint is copy-pasteable ---------------------------------------
# One assertion per hint: a quoting bug once survived review because only one
# hint was ever asserted.
assert_contains "$ref_out" "restore $ref_fixture/hypr/config/spaced\\ dir/gone.conf, or drop the source line from $ref_fixture/hypr/hyprland.conf" \
    "source hint shell-quotes a target containing a space"
assert_contains "$ref_out" "restore $ref_fixture/gone/missing2.sh, or drop the reference from $ref_fixture/has\\ space.sh" \
    "literal hint shell-quotes the referencing file's name"
assert_contains "$ref_out" "change the wallpaper (Super+Ctrl+W)" \
    "palette hint offers the wallpaper carousel without requiring a saved selection"
assert_contains "$ref_out" "$ref_fixture/scripts/theming/generate-palette.sh /path/to/wallpaper.jpg" \
    "palette hint accepts an image even without a saved wallpaper"
assert_not_contains "$ref_out" "$ref_cache_empty/current_wallpaper" \
    "palette hint does not depend on a missing wallpaper symlink"
assert_contains "$ref_out" "$ref_fixture/scripts/theming/apply-wal.sh" \
    "palette hint also renders every component's cache"

# A top-level conf has no base directory; "$root//$target" would be an ugly,
# unpasteable path even though the kernel tolerates it.
assert_contains "$ref_out" "restore $ref_fixture/toplevel-target.conf" \
    "hint for a top-level conf has no doubled slash"
assert_not_contains "$ref_out" "$ref_fixture//" "no hint contains a doubled slash"

# `<foo>` is input redirection to a shell, so the user would get an error from
# bash rather than from the command they pasted.
assert_not_contains "$ref_out" "<" "no hint contains what a shell reads as a redirection"

# --- the all-clear is reserved for an actually clear result -----------------
assert_not_contains "$ref_out" "✓" "repo with broken references gets no green tick"

# =====================================================================
# A repo where everything resolves.
# =====================================================================
ref_clean="$(make_fixture)"
mkdir -p "$ref_clean/hypr/config"
cat > "$ref_clean/hypr/hyprland.conf" <<'EOF'
source = config/colors.conf
EOF
echo "colors" > "$ref_clean/hypr/config/colors.conf"
cat > "$ref_clean/hypr/hyprland.lua" <<'EOF'
require("config.colors")
EOF
echo "return {}" > "$ref_clean/hypr/config/colors.lua"
cat > "$ref_clean/launch.sh" <<'EOF'
exec "$HOME/.config/hypr/hyprland.conf"
EOF
git -C "$ref_clean" add -A
git -C "$ref_clean" commit -qm "fixture"

ref_cache_full="$DOCTOR_TEST_TMP/ref-cache full"
mkdir -p "$ref_cache_full/wal"
echo "generated" > "$ref_cache_full/wal/colors-hyprland.conf"
echo "return {}" > "$ref_cache_full/wal/colors-hyprland.lua"
echo "#0e1416" > "$ref_cache_full/wal/colors"
echo "surface=#0e1416" > "$ref_cache_full/wal/roles"

DOCTOR_ROOT="$ref_clean"
DOCTOR_CACHE="$ref_cache_full"
doctor_reset
check_references > "$ref_out_file" 2>&1
ref_clean_out="$(<"$ref_out_file")"

assert_contains "$ref_clean_out" "✓" "fully resolvable repo gets the green tick"
assert_contains "$ref_clean_out" "all config references resolve" \
    "fully resolvable repo says so"
assert_eq "$DOCTOR_ERRORS" "0" "fully resolvable repo records no errors"
assert_eq "$DOCTOR_WARNINGS" "0" "fully resolvable repo records no warnings"
assert_eq "$DOCTOR_NOTICES" "0" "fully resolvable repo records no notices"

# Each missing input warns even with both Hyprland outputs present.
for ref_name in colors roles; do
    mv "$ref_cache_full/wal/$ref_name" "$ref_cache_full/$ref_name.saved"
    doctor_reset
    check_references > "$ref_out_file" 2>&1
    ref_missing_out="$(<"$ref_out_file")"
    assert_contains "$ref_missing_out" "palette cache missing: $ref_cache_full/wal/$ref_name" \
        "missing $ref_name is reported independently"
    assert_eq "$DOCTOR_ERRORS" "0" "missing $ref_name produces no errors"
    assert_eq "$DOCTOR_WARNINGS" "1" "missing $ref_name produces exactly one warning"
    assert_eq "$DOCTOR_NOTICES" "0" "missing $ref_name produces no notices"
    assert_not_contains "$ref_missing_out" "✓" \
        "missing $ref_name gets no all-clear"
    assert_contains "$ref_missing_out" "$(doctor_q "$ref_clean/scripts/theming/generate-palette.sh") $(doctor_q /path/to/wallpaper.jpg) && $(doctor_q "$ref_clean/scripts/theming/apply-wal.sh")" \
        "palette hint supplies a valid image argument and component rendering command"
    mv "$ref_cache_full/$ref_name.saved" "$ref_cache_full/wal/$ref_name"
done

# =====================================================================
# A repo whose only finding is a warning.
# =====================================================================
# ok is the all-clear and nothing else: gating it on the error count alone
# would print a green tick over a warning the reader is meant to act on.
ref_warn_fixture="$(make_fixture)"
cat > "$ref_warn_fixture/warn-only.sh" <<'EOF'
#!/bin/bash
"$HOME/.config/gone/warn-only.sh"
EOF
git -C "$ref_warn_fixture" add -A
git -C "$ref_warn_fixture" commit -qm "fixture"

DOCTOR_ROOT="$ref_warn_fixture"
DOCTOR_CACHE="$ref_cache_full"
doctor_reset
check_references > "$ref_out_file" 2>&1
ref_warn_out="$(<"$ref_out_file")"

assert_contains "$ref_warn_out" "WARN" "warning-only repo still reports its warning"
assert_not_contains "$ref_warn_out" "✓" "a warning suppresses the all-clear line"
assert_eq "$DOCTOR_ERRORS" "0" "warning-only repo records no error"
assert_eq "$DOCTOR_WARNINGS" "1" "warning-only repo records one warning"

# =====================================================================
# A repo with no configs at all.
# =====================================================================
# Nothing to resolve is a clear result, not a notice: an empty target list is a
# normal outcome, and doctor_require_repo has already ruled out "no repository".
ref_bare_fixture="$(make_fixture)"
echo "plain" > "$ref_bare_fixture/regular-file"
git -C "$ref_bare_fixture" add -A
git -C "$ref_bare_fixture" commit -qm "fixture"

DOCTOR_ROOT="$ref_bare_fixture"
DOCTOR_CACHE="$ref_cache_full"
doctor_reset
check_references > "$ref_out_file" 2>&1
ref_bare_out="$(<"$ref_out_file")"

assert_contains "$ref_bare_out" "all config references resolve" \
    "repo without configs is a clear result"
assert_eq "$DOCTOR_ERRORS" "0" "repo without configs records no errors"
assert_eq "$DOCTOR_WARNINGS" "0" "repo without configs records no warnings"
assert_eq "$DOCTOR_NOTICES" "0" "repo without configs records no notices"
