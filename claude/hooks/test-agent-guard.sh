#!/usr/bin/env bash
# Tests for agent-guard.sh: it refuses the Agent tool inside Herdr and stays
# silent outside it, and the tracked settings register it exactly once even
# when apply-settings.sh runs twice. Never touches the real ~/.claude.
#   bash claude/hooks/test-agent-guard.sh
set -uo pipefail
here=$(dirname "$(readlink -f "$0")")
repo=$(cd "$here/../.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { echo "ok   $1"; }
no() { echo "FAIL $1"; fail=1; }
reason="Inside Herdr every subagent runs in a pane: use the delegate skill (pane.sh). A skill's 'dispatch a subagent' names the role, not the tool."

out=$(echo '{"tool_name":"Agent"}' | env HERDR_ENV=1 sh "$here/agent-guard.sh" 2>&1); rc=$?
if [ "$rc" = 0 ] \
   && [ "$(jq -r .hookSpecificOutput.hookEventName <<<"$out" 2>/dev/null)" = PreToolUse ] \
   && [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$out" 2>/dev/null)" = deny ] \
   && [ "$(jq -r .hookSpecificOutput.permissionDecisionReason <<<"$out" 2>/dev/null)" = "$reason" ]
then ok "inside Herdr: Agent denied with the pane reason"; else no "inside Herdr: rc $rc, out '$out'"; fi

for v in unset '' 0; do
  if [ "$v" = unset ]; then out=$(echo '{}' | env -u HERDR_ENV sh "$here/agent-guard.sh" 2>&1); rc=$?
  else out=$(echo '{}' | env HERDR_ENV="$v" sh "$here/agent-guard.sh" 2>&1); rc=$?; fi
  if [ "$rc" = 0 ] && [ -z "$out" ]; then ok "HERDR_ENV=$v: silent, allowed"
  else no "HERDR_ENV=$v: rc $rc, out '$out'"; fi
done

cmd='sh ~/.claude/hooks/agent-guard.sh'
count() { jq --arg c "$cmd" '[.hooks.PreToolUse[]? | select(.matcher == "Agent") | .hooks[] | select(.command == $c)] | length' "$1"; }
if [ "$(count "$repo/claude/settings.json")" = 1 ]; then ok "tracked settings register the guard on Agent"
else no "tracked settings: guard not registered on Agent"; fi

# apply-settings merges hooks by script name: a re-run must replace, not duplicate.
mkdir -p "$tmp/cfg/hooks"; : > "$tmp/cfg/hooks/agent-guard.sh"
CLAUDE_CONFIG_DIR="$tmp/cfg" bash "$repo/claude/apply-settings.sh" >/dev/null 2>&1
CLAUDE_CONFIG_DIR="$tmp/cfg" bash "$repo/claude/apply-settings.sh" >/dev/null 2>&1
if [ "$(count "$tmp/cfg/settings.json" 2>/dev/null)" = 1 ]; then ok "apply-settings twice: one guard"
else no "apply-settings twice: $(count "$tmp/cfg/settings.json" 2>/dev/null) guards"; fi

exit "$fail"
