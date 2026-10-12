---
name: codex-review
description: Use when the user asks Codex specifically to review code or a diff (e.g. "get codex to review this", "have codex look over my changes"), or when running /codex-review. Alias for delegate-review with the reviewer pinned to Codex.
---

# Codex Review

Alias. Invoke `delegate-review` with **reviewer `codex`**. The Codex alias and
effort come from *Review tier* in `~/.claude/skills/_shared/review.md`, the
single authority on both. `astra` only when the user explicitly asks for it.
Never `ultra`.

**The adversarial pairing rule still applies.** If Codex wrote the code under
review, a Codex review would be same-family self-review: route it to Claude
(model per *Review tier*) instead and tell the user you did, rather than silently honouring the
alias.

The review is blind — it gets the diff, the goal and the acceptance criteria,
never the implementer's report. Verify every finding against the actual code
before relaying it. See `delegate-review` and
`~/.claude/skills/_shared/review.md`.
