# Tests for scripts/doctor/checks/symlinks.sh — sourced by run-tests.sh
#
# Sourced fragment, never executed directly, so it carries no shebang; the
# directive below tells shellcheck which shell to assume (SC2148).
# shellcheck shell=bash
#
# Checks are run ONCE, redirected to a file under $DOCTOR_TEST_TMP, and the
# output is read back. `out="$(check_x)"` would run the check in a subshell and
# discard its severity counters, forcing a second run to observe them — so the
# asserted text and the asserted counts would come from different executions.

# shellcheck source=/dev/null
source "$DOCTOR_DIR/lib.sh"
# shellcheck source=/dev/null
source "$DOCTOR_DIR/checks/symlinks.sh"

# Assigned throughout this file but read only by the check sourced above — a
# cross-file use that SC2034 cannot see. Declare it external.
export DOCTOR_ROOT


# --- a repo containing every symlink state the check classifies ---
sym_fixture="$(make_fixture)"

mkdir -p "$sym_fixture/target-dir" "$sym_fixture/sub"
echo "real" > "$sym_fixture/target-dir/real-file"

# healthy: relative, resolves to a file
ln -s "../target-dir/real-file" "$sym_fixture/sub/good-relative"
# healthy: relative, resolves to a directory
ln -s "../target-dir" "$sym_fixture/sub/good-dir-link"
# error: relative target does not exist
ln -s "../target-dir/nonexistent" "$sym_fixture/sub/relative-dangling"
# error: absolute AND broken — reported as unresolvable, not as non-portable
ln -s "/home/someone/nowhere/missing-file" "$sym_fixture/sub/absolute-dangling"
# error: a path with a space, so the fix hint has to be shell-quoted
ln -s "../target-dir/nonexistent" "$sym_fixture/sub/spaced dangling"
# error: a symlink loop. -e fails on it exactly as it does on a missing target
ln -s "loop-b" "$sym_fixture/sub/loop-a"
ln -s "loop-a" "$sym_fixture/sub/loop-b"
# warn: absolute but resolving. The fixture lives under $TMPDIR, so this is the
# general "absolute target" case rather than a literal /home/... one.
ln -s "$sym_fixture/target-dir/real-file" "$sym_fixture/sub/absolute-resolving"
# error: git has it as a symlink, the working tree has a regular file
ln -s "../target-dir/real-file" "$sym_fixture/sub/clobbered-by-file"
# error: git has it as a symlink, the working tree has nothing
ln -s "../target-dir/real-file" "$sym_fixture/sub/deleted-entirely"

commit_fixture "$sym_fixture"

# Break the last two only after committing, so the index still records mode
# 120000 for them — the index is what the check derives its list from.
rm "$sym_fixture/sub/clobbered-by-file"
echo "not a link" > "$sym_fixture/sub/clobbered-by-file"
rm "$sym_fixture/sub/deleted-entirely"

DOCTOR_ROOT="$sym_fixture"
run_check check_symlinks

assert_contains "$CHECK_OUT" "relative-dangling" "unresolvable relative symlink is reported"
assert_contains "$CHECK_OUT" "ERROR" "unresolvable symlink is ERROR severity"
assert_contains "$CHECK_OUT" "absolute-dangling" "unresolvable absolute symlink is reported"
assert_contains "$CHECK_OUT" "absolute-resolving" "absolute-but-resolving symlink is reported"
assert_contains "$CHECK_OUT" "WARN" "absolute symlink is WARN severity"
assert_contains "$CHECK_OUT" "clobbered-by-file" "symlink replaced by a regular file is reported"
assert_contains "$CHECK_OUT" "deleted-entirely" "symlink missing from the working tree is reported"
assert_not_contains "$CHECK_OUT" "good-relative" "healthy relative symlink produces no finding"
assert_not_contains "$CHECK_OUT" "good-dir-link" "healthy symlink to a directory produces no finding"
assert_not_contains "$CHECK_OUT" "✓" "repo with broken symlinks gets no green tick"

# A loop is broken, but it is not missing — "dangling" would send the reader
# hunting for a target that is sitting right there.
assert_contains "$CHECK_OUT" "sub/loop-a → loop-b (does not resolve)" "symlink loop is not called dangling"
assert_not_contains "$CHECK_OUT" "dangling)" "no finding uses the word dangling"

# absolute-dangling is both absolute and broken; the if/elif reports it as
# unresolvable only, so it lands in the error tally rather than the warning one.
assert_eq "$DOCTOR_ERRORS" "7" "unresolvable, clobbered and missing symlinks counted as errors"
assert_eq "$DOCTOR_WARNINGS" "1" "one absolute resolving symlink counted as warning"

# --- every fix hint is copy-pasteable ---
# One assertion per hint: the quoting bug survived review because only the
# non-portable hint was ever asserted.
assert_contains "$CHECK_OUT" "ln -sfn ../target-dir/real-file $sym_fixture/sub/absolute-resolving" \
    "non-portable hint gives the relative target to use"
assert_contains "$CHECK_OUT" "ln -sfn NEW_TARGET $sym_fixture/sub/relative-dangling" \
    "unresolvable hint uses a placeholder that is not shell syntax"
assert_not_contains "$CHECK_OUT" "<correct-target>" "no hint contains what a shell reads as a redirection"
assert_contains "$CHECK_OUT" "cp -a $sym_fixture/sub/clobbered-by-file $sym_fixture/sub/clobbered-by-file.bak && git -C $sym_fixture checkout -- sub/clobbered-by-file" \
    "clobbered hint backs the file up before checkout discards it"
assert_contains "$CHECK_OUT" "git -C $sym_fixture checkout -- sub/deleted-entirely" \
    "missing hint restores the link from the index"
# The bug this catches: an unquoted path with a space is two arguments to ln.
assert_contains "$CHECK_OUT" "ln -sfn NEW_TARGET $sym_fixture/sub/spaced\\ dangling" \
    "hint shell-quotes a path containing a space"

# --- the relative-target suggestion degrades gracefully ---
# Shadow realpath so the ${relative:-NEW_TARGET} fallback is exercised; the
# check runs in this shell, so a function definition shadows the binary.
realpath() { return 1; }
run_check check_symlinks
unset -f realpath
assert_contains "$CHECK_OUT" "ln -sfn NEW_TARGET $sym_fixture/sub/absolute-resolving" \
    "non-portable hint falls back to a placeholder when realpath fails"
assert_eq "$DOCTOR_WARNINGS" "1" "realpath failure does not change the classification"

# --- paths git would C-quote must still be read back verbatim ---
# `git ls-files -s` renders a path containing a quote or a non-ASCII byte as a
# C-style quoted string, which no longer names a file on disk. Reading the list
# NUL-delimited avoids that; without it these two links look unresolvable.
sym_quote_fixture="$(make_fixture)"
echo "real" > "$sym_quote_fixture/real-file"
ln -s "real-file" "$sym_quote_fixture/spaced link"
ln -s "real-file" "$sym_quote_fixture/ünicode-lïnk"
commit_fixture "$sym_quote_fixture"

DOCTOR_ROOT="$sym_quote_fixture"
run_check check_symlinks

assert_contains "$CHECK_OUT" "all 2 tracked symlinks" "quoted-path symlinks read back as healthy"
assert_eq "$DOCTOR_ERRORS" "0" "quoted paths are not mistaken for broken links"

# --- the all-clear line is reserved for an actually clear result ---
# A green tick over "0 of 2 healthy" is the one line a skim-reader would
# misread, so the ok line appears only when nothing is wrong.
assert_contains "$CHECK_OUT" "✓" "all-healthy repo gets the green tick"

# --- a repo with no tracked symlinks at all ---
# Not a warning: whether zero symlinks is suspicious depends on the repo, and
# doctor_require_repo has already ruled out the "not a repository" cause.
sym_bare_fixture="$(make_fixture)"
echo "plain" > "$sym_bare_fixture/regular-file"
commit_fixture "$sym_bare_fixture"

DOCTOR_ROOT="$sym_bare_fixture"
run_check check_symlinks

assert_contains "$CHECK_OUT" "no tracked symlinks found" "repo without symlinks says so"
assert_not_contains "$CHECK_OUT" "tracked symlinks are healthy" "no all-clear line without symlinks"
assert_eq "$DOCTOR_NOTICES" "1" "empty symlink list is a notice, not a warning"
assert_eq "$DOCTOR_ERRORS$DOCTOR_WARNINGS" "00" "empty symlink list is not an error or warning"
