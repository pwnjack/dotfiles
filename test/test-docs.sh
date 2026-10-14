#!/bin/bash
#
# Tests for the generated documentation.
#
# docs/keybindings.md is rendered from hypr/config/software/keybinds.lua. That
# only helps if a stale copy cannot be committed, which is what this suite is
# for: it lives in test/, whose owning directory is the repo root, so the
# pre-commit hook runs it on every commit -- including the commit that changes
# keybinds.lua and forgets to regenerate.
#
# Standalone and dependency-free, exit 1 on any failure, the same style as
# scripts/waybar/test-updates.sh.
#
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$TEST_DIR")"

GENERATOR="$ROOT/scripts/docs/generate-keybindings.sh"
CHEATSHEET="$ROOT/scripts/keybinds/keybinds-sheet.sh"
DOC="$ROOT/docs/keybindings.md"
CONF="$ROOT/hypr/config/software/keybinds.lua"

# shellcheck disable=SC1091 # Shared libraries are checked separately.
# shellcheck source=scripts/lib/assert.sh
. "$ROOT/scripts/lib/assert.sh"
# shellcheck disable=SC1091
# shellcheck source=scripts/lib/hypr-vars.sh
. "$ROOT/scripts/lib/hypr-vars.sh"

# --- the generated file is current ------------------------------------------

if out=$("$GENERATOR" --check 2>&1); then
    pass "docs/keybindings.md is up to date"
else
    fail "docs/keybindings.md is out of date" \
        "run ./scripts/docs/generate-keybindings.sh and commit the result" \
        "$out"
fi

# --- the check would actually catch a stale file -----------------------------
#
# A checker that always passes is worse than none. Run the actual generator
# and parser in a fixture tree, so the deliberate stale edit never changes the
# tracked document while other suites read this repository.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/docs" "$TMP/scripts/docs" "$TMP/scripts/keybinds" "$TMP/scripts/lib" \
    "$TMP/hypr/config/software"
cp "$GENERATOR" "$TMP/scripts/docs/"
cp "$CHEATSHEET" "$TMP/scripts/keybinds/"
cp "$ROOT/scripts/lib/hypr-vars.sh" "$TMP/scripts/lib/"
cp "$CONF" "$TMP/hypr/config/software/"
cp "$ROOT/hypr/config/apptype.lua" "$TMP/hypr/config/"
cp "$DOC" "$TMP/docs/keybindings.md"
if "$TMP/scripts/docs/generate-keybindings.sh" --check >/dev/null 2>&1; then
    pass "--check accepts the unchanged fixture document"
else
    fail "the fixture must pass before testing a stale document"
fi
# shellcheck disable=SC2016 # Literal Markdown backticks.
printf '\n| `Super + Nonexistent` | Not a real binding |\n' >> "$TMP/docs/keybindings.md"
if "$TMP/scripts/docs/generate-keybindings.sh" --check >/dev/null 2>&1; then
    fail "--check accepts a doctored file" \
        "the staleness gate does not actually gate anything"
else
    pass "--check rejects a doctored file"
fi

# --- every binding reaches the document --------------------------------------
#
# The generator could regenerate a file that is internally consistent and still
# wrong, if the markdown renderer dropped rows. Count the bind lines the config
# declares and the key cells the document carries, and require the document to
# account for all of them. Folded rows (`Super + 1-9, 0, =`) mean the two counts
# are not equal, so this compares reachable sections instead: every `## Heading`
# in keybinds.lua that carries at least one bind must appear in the document.

missing=()
section=""
has_bind=0
# Not `cmd | while read`: the loop assigns to `missing`, which a subshell would
# discard -- the same trap the doctor's check modules document.
while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^[[:space:]]*--[[:space:]]*##[[:space:]]+(.*)$ ]]; then
        if [ "$has_bind" -eq 1 ] && [ -n "$section" ]; then
            grep -qF "## $section" "$DOC" || missing+=("$section")
        fi
        section="${BASH_REMATCH[1]%"${BASH_REMATCH[1]##*[![:space:]]}"}"
        has_bind=0
        continue
    fi
    [[ "$line" =~ ^[[:space:]]*hl\.bind\( ]] && has_bind=1
done < "$CONF"
if [ "$has_bind" -eq 1 ] && [ -n "$section" ]; then
    grep -qF "## $section" "$DOC" || missing+=("$section")
fi

if [ "${#missing[@]}" -eq 0 ]; then
    pass "every keybinds.lua section with bindings has a heading in the document"
else
    fail "sections missing from docs/keybindings.md" "${missing[@]}"
fi

# --- row count matches the runtime overlay -----------------------------------
#
# All skins walk the same ORDER, so a row present in one and absent from another
# means a renderer lost something.

print_rows=$("$CHEATSHEET" --print | grep -c '^  ')
md_rows=$("$CHEATSHEET" --markdown | grep -c '^| `')
json_rows=$("$CHEATSHEET" --json | jq '[.sections[].rows[]] | length')
if [ "$print_rows" -eq "$md_rows" ] && [ "$print_rows" -eq "$json_rows" ]; then
    pass "plain, markdown and JSON renderings agree on $md_rows rows"
else
    fail "renderings disagree on row count" \
        "--print: $print_rows, --markdown: $md_rows, --json: $json_rows"
fi

# --- every label fits the Super+H overlay ------------------------------------
#
# The overlay's own suite only runs when quickshell/keybinds-overlay/ changes,
# but a label is edited in keybinds.lua. Its elision check renders the real
# sheet, so it belongs to every commit, the same as this file does.

if out=$(bash "$ROOT/quickshell/keybinds-overlay/test/run-tests.sh" Overlay::test_no_real_label_is_elided 2>&1); then
    pass "no keybinds.lua label is elided in the overlay"
else
    # The same suite also fails for a missing tool or a broken model test, so
    # show what failed rather than assuming it was a label.
    fail "the overlay's label check failed (\"labels elided\" below means: shorten that comment)" \
        "$(printf '%s\n' "$out" | grep -E 'FAIL|Actual|required|not found|rror' | head -5)"
fi

# --- per-user values are not frozen into the document ------------------------
#
# options/terminal and options/browser are read at Hyprland parse time, so their
# values are this machine's. Committing them would restate the drift the
# generated document exists to prevent.

frozen=()
while IFS= read -r name; do
    # The tracked default: options/ is this machine's rendered copy and is not in a commit.
    [ -f "$ROOT/defaults/options/$name" ] || { frozen+=("$name: defaults/options/$name is missing"); continue; }
    value="$(head -n1 "$ROOT/defaults/options/$name")"
    [ -n "$value" ] || { frozen+=("$name: defaults/options/$name is empty"); continue; }
    grep -qF "options/$name" "$DOC" || frozen+=("$name: no reference to options/$name")
    if grep -qi "(\`\?$value\`\?)" "$DOC"; then
        frozen+=("$name: the document names '$value' instead of options/$name")
    fi
done < <(
    # apptype.lua's read_option() calls, kept to the names hypr_var_origin owns.
    sed -n 's/^[[:space:]]*\([a-z]*\)[[:space:]]*=[[:space:]]*read_option("\1".*/\1/p' \
        "$ROOT/hypr/config/apptype.lua" |
        while IFS= read -r candidate; do
            [ "$(hypr_var_origin "$candidate")" = options ] && printf '%s\n' "$candidate"
        done
)

if [ "${#frozen[@]}" -eq 0 ]; then
    pass "options-backed values are named by file, not by this machine's answer"
else
    fail "per-user values leaked into the document" "${frozen[@]}"
fi

# --- summary -----------------------------------------------------------------

# shellcheck disable=SC2119 # No summary name is intentional.
test_summary
