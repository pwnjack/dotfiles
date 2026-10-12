---
name: claude-review
description: Use when the user explicitly asks to spawn or watch a separate, visible Claude subagent pane for a code review (e.g. "get a claude subagent to review this", "spin up another claude to review my changes"), or when running /claude-review. Alias for delegate-review with the reviewer pinned to Claude. For normal review requests, use auto-subagent-routing instead.
---

# Claude Review

Alias. Invoke `delegate-review` with **reviewer `claude`**. The Claude alias
comes from *Review tier* in `~/.claude/skills/_shared/review.md`, the single
authority on it — or, with no usable Codex, from the degraded cross-model
pairing there. `fable` only when the user explicitly asks for it.

**The adversarial pairing rule still applies.** If a Claude subagent or the
orchestrator wrote the code under review, a Claude review would be same-family
self-review: route it to **Codex** instead and tell the user you did, rather
than silently honouring the alias.

This is the correct reviewer in exactly two cases: Codex wrote the code, or the
capability probe found no usable Codex, where the rule degrades to
cross-model plus fresh context.

The review is blind — it gets the diff, the goal and the acceptance criteria,
never the implementer's report. Verify every finding against the actual code
before relaying it. See `delegate-review` and
`~/.claude/skills/_shared/review.md`.
