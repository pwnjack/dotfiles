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

out=$(env HERDR_ENV=1 sh "$here/agent-guard.sh" <<<'{"tool_name":"Agent"}' 2>&1); rc=$?
if [ "$rc" = 0 ] \
   && [ "$(jq -r .hookSpecificOutput.hookEventName <<<"$out" 2>/dev/null)" = PreToolUse ] \
   && [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$out" 2>/dev/null)" = deny ] \
   && [ "$(jq -r .hookSpecificOutput.permissionDecisionReason <<<"$out" 2>/dev/null)" = "$reason" ]
then ok "inside Herdr: Agent denied with the pane reason"; else no "inside Herdr: rc $rc, out '$out'"; fi

# Input comes from a here-string, not `echo |`: the hook exits without reading
# it outside Herdr, and a writer still running then dies of SIGPIPE, which
# pipefail turns into a 141 on a loaded machine.
for v in unset '' 0; do
  if [ "$v" = unset ]; then out=$(env -u HERDR_ENV sh "$here/agent-guard.sh" <<<'{}' 2>&1); rc=$?
  else out=$(env HERDR_ENV="$v" sh "$here/agent-guard.sh" <<<'{}' 2>&1); rc=$?; fi
  if [ "$rc" = 0 ] && [ -z "$out" ]; then ok "HERDR_ENV=$v: silent, allowed"
  else no "HERDR_ENV=$v: rc $rc, out '$out'"; fi
done

# The registered command runs the script in the repo, like the status line, so
# it works whatever CLAUDE_CONFIG_DIR is; run it as Claude would, through a shell.
cmd='sh ~/.config/claude/hooks/agent-guard.sh'
count() { jq --arg c "$cmd" '[.hooks.PreToolUse[]? | select(.matcher == "Agent") | .hooks[] | select(.command == $c)] | length' "$1"; }
if [ "$(count "$repo/claude/settings.json")" = 1 ]; then ok "tracked settings register the guard on Agent"
else no "tracked settings: guard not registered on Agent"; fi
reg=$(jq -r '[.hooks.PreToolUse[]? | select(.matcher == "Agent") | .hooks[].command] | first // "false"' "$repo/claude/settings.json")
out=$(env HERDR_ENV=1 CLAUDE_CONFIG_DIR="$tmp/elsewhere" sh -c "$reg" <<<'{}' 2>&1)
if [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$out" 2>/dev/null)" = deny ]
then ok "registered command denies with a custom CLAUDE_CONFIG_DIR"; else no "registered command: out '$out'"; fi

# apply-settings merges hooks by script name: a re-run must replace, not duplicate.
mkdir -p "$tmp/cfg"
CLAUDE_CONFIG_DIR="$tmp/cfg" bash "$repo/claude/apply-settings.sh" >/dev/null 2>&1
CLAUDE_CONFIG_DIR="$tmp/cfg" bash "$repo/claude/apply-settings.sh" >/dev/null 2>&1
if [ "$(count "$tmp/cfg/settings.json" 2>/dev/null)" = 1 ]; then ok "apply-settings twice: one guard"
else no "apply-settings twice: $(count "$tmp/cfg/settings.json" 2>/dev/null) guards"; fi

exit "$fail"
