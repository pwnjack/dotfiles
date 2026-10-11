#!/bin/sh
# Non-blocking PreToolUse hook, matched on the Agent tool: reminds the model to
# consult the auto-subagent-routing skill BEFORE it spawns a Claude subagent.
# Only inside a live Herdr session.
#
# WHY PreToolUse RATHER THAN UserPromptSubmit. This started as a
# UserPromptSubmit hook, so it fired on every user message regardless of whether
# a dispatch was imminent. Identical text on a dozen consecutive turns reads as
# ambient noise, and it was in fact skipped across a whole session's worth of
# subagent dispatches on 2026-08-02. Firing on the Agent tool call instead puts
# the reminder at the decision point, where it is actionable.
#
# It deliberately does NOT fire on the Codex path: delegate-implement and
# delegate-review drive a Herdr pane through Bash, not through Agent. So this
# fires exactly when a Claude subagent is about to be spawned — precisely the
# case where the adversarial pairing and the leaf guard matter most.
#
# Advisory by choice (2026-08-02). PreToolUse can hard-gate with
# permissionDecision "ask", which cannot be skipped, but that prompts on every
# Agent call including read-only Explore agents. Swap the payload below if the
# advisory version proves too easy to ignore.
[ "${HERDR_ENV:-}" = "1" ] || exit 0
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"About to spawn a Claude subagent. Consult auto-subagent-routing FIRST — it owns who implements and who reviews. Claude sonnet is the default implementer; well-specified self-contained work goes to Codex via delegate-implement. REVIEW IS ADVERSARIAL: the reviewer is never the same family as the implementer, so Claude-written code is reviewed by Codex and Codex-written code by Claude (model per the Review tier in handoff.md). The reviewer gets the diff, goal and acceptance criteria only — never the implementer report. Any subagent you spawn is a LEAF WORKER: put the [LEAF WORKER — DO NOT DELEGATE] marker at the top of its brief so it cannot delegate onward (the Agent tool cannot set CLAUDE_AGENT_DEPTH; herdr-spawn.sh sets it on panes)."}}'
