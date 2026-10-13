#!/usr/bin/env bash
# Integrity checks for the tracked agent harness: skill frontmatter, files the
# skills and global instructions name, the "no pinned model id" rule, and that
# every listed plugin has a registered marketplace. Static only; never touches
# Herdr, Codex or a live ~/.claude.
#   bash claude/skills/test-skills.sh
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
claude=$(dirname "$here")
fail=0

check() { # check <description> <command...>
  local what=$1; shift
  if "$@" >/dev/null 2>&1; then echo "  ok   $what"; else echo "  FAIL $what"; fail=1; fi
}

# --- every skill directory has a SKILL.md whose name is the directory name ----
for d in "$here"/*/; do
  d=${d%/} n=$(basename "$d") f="$d/SKILL.md"
  check "$n: SKILL.md exists" test -f "$f"
  [ -f "$f" ] || continue
  check "$n: frontmatter name matches directory" \
    bash -c 'sed -n "2p" "$1" | grep -qx "name: $2"' _ "$f" "$n"
  check "$n: has a description" bash -c 'sed -n "3p" "$1" | grep -q "^description: ."' _ "$f"
done

# --- every ~/.claude/skills/<path> the instructions name exists in the repo ---
missing=0
# shellcheck disable=SC2088  # a literal ~ path, matched as text
while IFS= read -r ref; do
  [ -e "$here/$ref" ] || { echo "  FAIL ~/.claude/skills/$ref is referenced but missing"; missing=1; }
done < <(grep -rhoE '~/\.claude/skills/[A-Za-z0-9._/-]+' "$here" "$claude/CLAUDE.global.md" \
           --include='*.md' --include='*.sh' | sed 's#^~/\.claude/skills/##' | sort -u)
[ "$missing" = 0 ] && echo "  ok   every referenced skill file exists" || fail=1
check "global instructions name an existing skill" \
  bash -c 'grep -q "\`delegate\` skill" "$1" && test -f "$2/delegate/SKILL.md"' _ "$claude/CLAUDE.global.md" "$here"

# --- no pinned model identifiers in instruction text (names go stale) ---------
check "no pinned model ids in skill or instruction text" \
  bash -c '! grep -rEq "claude-(opus|sonnet|haiku|fable)-[0-9]|gpt-[0-9]" "$1" "$2" --include="*.md"' \
  _ "$here" "$claude/CLAUDE.global.md"

# --- settings: valid JSON, and no listed plugin without its marketplace --------
settings="$claude/settings.json"
check "settings.json is valid JSON" jq -e . "$settings"
orphans=$(jq -r '(.extraKnownMarketplaces // {} | keys) as $m
  | (.enabledPlugins // {}) | keys[] | select((split("@")[1]) as $mk | ($m | index($mk)) == null)' "$settings" 2>/dev/null)
if [ -z "$orphans" ]; then echo "  ok   every listed plugin has a registered marketplace"
else echo "  FAIL plugin without a marketplace: $orphans"; fail=1; fi

exit "$fail"
