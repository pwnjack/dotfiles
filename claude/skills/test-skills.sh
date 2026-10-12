#!/usr/bin/env bash
# Integrity checks for the tracked agent harness: skill frontmatter, links
# between skills and the _shared contracts, the "no pinned model id" rule, the
# advisory hook, and that every enabled plugin has a registered marketplace.
# Static only; never touches Herdr, Codex or a live ~/.claude.
#   bash claude/skills/test-skills.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
claude=$(dirname "$here")
fail=0

check() { # check <description> <command...>
  local what=$1; shift
  if "$@" >/dev/null 2>&1; then echo "  ok   $what"; else echo "  FAIL $what"; fail=1; fi
}
has() { grep -qF -- "$2" "$1"; }

# --- every skill directory has a SKILL.md whose name is the directory name ----
skill_dirs=()
for d in "$here"/*/; do
  d=${d%/}; [ "$(basename "$d")" = _shared ] && continue
  skill_dirs+=("$d")
done
check "found skill directories" test "${#skill_dirs[@]}" -gt 0
for d in "${skill_dirs[@]}"; do
  n=$(basename "$d"); f="$d/SKILL.md"
  check "$n: SKILL.md exists" test -f "$f"
  [ -f "$f" ] || continue
  check "$n: frontmatter name matches directory" \
    bash -c 'sed -n "2p" "$1" | grep -qx "name: $2"' _ "$f" "$n"
  check "$n: has a description" bash -c 'sed -n "3p" "$1" | grep -q "^description: ."' _ "$f"
done

# --- _shared is a library, not a skill; the two contracts keep their sections ---
check "_shared has no SKILL.md" test ! -e "$here/_shared/SKILL.md"
for h in "Capability probe" "Brief template" "Model selection" "Recursion guards" \
         "Launching a worker" "Dispatch and wait" "Pane lifecycle"; do
  check "handoff.md has '$h'" grep -q "^## $h" "$here/_shared/handoff.md"
done
for h in "Adversarial pairing" "Blindness rule" "Review idempotency" "Review tier"; do
  check "review.md has '$h'" grep -q "^## $h" "$here/_shared/review.md"
  check "handoff.md does not duplicate '$h'" bash -c '! grep -q "^## $1" "$2"' _ "$h" "$here/_shared/handoff.md"
done

# --- every _shared/<file> a skill, hook or instruction names exists ------------
missing=0
while IFS= read -r ref; do
  [ -e "$here/_shared/$ref" ] || { echo "  FAIL _shared/$ref is referenced but missing"; missing=1; }
done < <(grep -rhoE '_shared/[A-Za-z0-9._-]+' "$here" "$claude/CLAUDE.global.md" "$claude/hooks" \
           --include='*.md' --include='*.sh' --exclude='test-skills.sh' | sed 's#^_shared/##' | sort -u)
[ "$missing" = 0 ] && echo "  ok   every referenced _shared file exists" || fail=1

# --- every skill named in backticks exists ------------------------------------
missing=0
while IFS= read -r s; do
  [ -d "$here/$s" ] || { echo "  FAIL skill '$s' is referenced but missing"; missing=1; }
done < <(grep -rhoE '`(auto-subagent-routing|(delegate|codex|claude)-(implement|review))`' \
           "$here" "$claude/CLAUDE.global.md" --include='*.md' | tr -d '`' | sort -u)
[ "$missing" = 0 ] && echo "  ok   every referenced skill exists" || fail=1

# --- no pinned model identifiers in any skill text (names go stale) -----------
check "no pinned model ids in skill text" \
  bash -c '! grep -rEq "claude-(opus|sonnet|haiku|fable)-[0-9]|gpt-[0-9]" "$1" --include="*.md"' _ "$here"

# --- the advisory hook: silent outside Herdr, valid JSON inside ----------------
hook="$claude/hooks/auto-subagent-reminder.sh"
check "hook is silent outside Herdr" bash -c '[ -z "$(env -u HERDR_ENV sh "$1")" ]' _ "$hook"
check "hook emits valid JSON inside Herdr" bash -c 'HERDR_ENV=1 sh "$1" | jq -e . >/dev/null' _ "$hook"
check "hook keeps the leaf-worker marker" bash -c 'HERDR_ENV=1 sh "$1" | grep -qF "LEAF WORKER"' _ "$hook"

# --- settings: valid JSON, and no enabled plugin without its marketplace -------
settings="$claude/settings.json"
check "settings.json is valid JSON" jq -e . "$settings"
orphans=$(jq -r '(.extraKnownMarketplaces // {} | keys) as $m
  | (.enabledPlugins // {}) | keys[] | select((split("@")[1]) as $mk | ($m | index($mk)) == null)' "$settings" 2>/dev/null)
if [ -z "$orphans" ]; then echo "  ok   every enabled plugin has a registered marketplace"
else echo "  FAIL enabled plugin without a marketplace: $orphans"; fail=1; fi
orphans=$(jq -r '(.enabledPlugins // {}) as $e
  | (.pluginConfigs // {}) | keys[] | select($e[.] == null)' "$settings" 2>/dev/null)
if [ -z "$orphans" ]; then echo "  ok   every plugin config belongs to an enabled plugin"
else echo "  FAIL plugin config without an enabled plugin: $orphans"; fail=1; fi

exit "$fail"
