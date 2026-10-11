---
name: claude-implement
description: Use when the user explicitly asks to spawn or watch a separate, visible Claude subagent pane for implementation (e.g. "spin up a claude subagent for X", "have another claude implement Y so I can watch"), or when running /claude-implement. Alias for delegate-implement with the executor pinned to a Claude pane. For normal implementation requests, use auto-subagent-routing instead.
---

# Claude Implement

Alias. Invoke `delegate-implement` with **executor `claude-pane`**.

Pick the alias from the task shape — `haiku` for bulk mechanical work, `sonnet`
for standard implementation, `opus` for deep architecture or ambiguous
requirements. `fable` only when the user explicitly asks for it. Never a
pinned model id.

This launches an independent `claude` CLI process. It shares none of this
conversation, this memory, or this task list, so the brief must be fully
self-contained.

Two guards are mandatory (see *Recursion guards* in
`~/.claude/skills/_shared/handoff.md`): `CLAUDE_AGENT_DEPTH=1` on the pane and
the `--append-system-prompt` leaf directive. `herdr-spawn.sh` applies both, so
always launch through it and never hand-roll the split. Without them a Claude
subagent reads the global routing policy and delegates in turn.

Per the adversarial pairing rule, code a Claude pane writes is reviewed by
**Codex** — not by another Claude.
