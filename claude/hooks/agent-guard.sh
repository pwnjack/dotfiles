#!/bin/sh
# PreToolUse hook on the Agent tool. Inside Herdr every subagent runs in a
# visible pane through the delegate skill, but Superpowers and other skills
# name the Agent tool when they dispatch one; this refuses it there and points
# at delegate. Outside Herdr it is silent: the Agent tool is the fallback.
[ "${HERDR_ENV:-}" = 1 ] || exit 0
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Inside Herdr every subagent runs in a pane: use the delegate skill (pane.sh). A skill'"'"'s '"'"'dispatch a subagent'"'"' names the role, not the tool."}}'
