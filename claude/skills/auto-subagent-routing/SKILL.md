---
name: auto-subagent-routing
description: Use at the start of any implementation or code-review task, and before declaring any code change complete, to decide who does the work and who reviews it. Picks executor and capability tier, pairs the reviewer adversarially against the implementer, and degrades gracefully when Codex or Herdr is unavailable. Governs when to use delegate-implement and delegate-review.
---

# Auto Subagent Routing

Decides **who** does a piece of work and **who reviews it**.
`delegate-implement` and `delegate-review` define how each mechanism works; this
skill decides which to reach for. Worker mechanics live in
`~/.claude/skills/_shared/handoff.md`, review rules in
`~/.claude/skills/_shared/review.md`.

This skill applies **everywhere**: outside a Herdr session it selects the
native `Agent` tool rather than switching itself off.

## Invariants

Where a later section appears to conflict with one of these, the invariant wins.

1. **Adversarial review.** Whenever both families are available, the reviewer is
   never from the same family as the implementer. With only one family left the
   guarantee degrades rather than silently pretending to hold.
2. **Blind review.** The reviewer never sees the implementer's report.
3. **Graceful degradation.** Losing Codex, or Herdr, or both, weakens the
   workflow by one notch and never breaks it.
4. **No hardcoded model identity.** Name roles and efforts; let identity resolve
   at delegation time.

## Step 1: Probe capability, once

Run both probes in `handoff.md` (**Capability probe**) and cache the answers for
the session: **axis 1**, can I drive a Herdr pane (otherwise the native `Agent`
tool), and **axis 2**, is Codex usable. Codex runs only in a Herdr pane, so the
full cross-family review guarantee needs both to pass; otherwise review takes
the degraded cross-model pairing.

A delegation that fails on auth or quota flips axis 2 for the rest of the
session. **Announce a degraded axis once**, then carry on. Never stop to ask,
never re-announce — and never report a degraded review as though it were the
full guarantee.

## Step 2: Pick the implementer

| Task shape | Executor |
|---|---|
| Trivial — one line, a rename, a config tweak, one tool call | **You, directly.** Delegation costs more than the change is worth |
| Bulk mechanical — boilerplate, scaffolding, repetitive edits | Claude `haiku`, or Codex `luna` at `low` |
| Small, well-specified, straightforward — one file, spec leaves nothing open | Codex `terra` at `medium` |
| **Standard implementation** | **Claude `sonnet`** — the default workhorse |
| Well-specified and self-contained, larger | **Codex** `sol` at `medium` — its lack of conversation context costs nothing here, and this offloads tokens to Codex's quota |
| Complex or subtle logic | Codex `sol` at `high` (`xhigh` when subtle), or Claude `opus` |
| Deep architecture, ambiguous requirements | **You, or Claude `opus`** when context isolation helps |
| Broad read-only exploration | Claude `haiku`; `sonnet` when it needs judgement |

Pick the lightest row that handles the task well. Moving up a row is for tasks
that need it, not insurance.

**Both families implement, deliberately.** If Codex never implemented, the
Claude-as-reviewer path would never run and would sit dormant until the day the
Codex subscription lapses — activating machinery that had never once executed.
Keeping both directions in continuous use is what makes losing Codex a shift in mix
rather than a leap into untested code.

If the user says they will do it themselves, or tells you to implement directly,
that overrides this table.

**Codex `astra` and Claude `fable` never come from this table.** They eat the
user's usage and run only when the user explicitly asks for them. Aliases
(`opus`, `sonnet`, `haiku`; `luna`, `terra`, `sol`) and the pinned-id and
`ultra` bans are covered in *Model selection* in `handoff.md`; every Codex
delegation names an alias **and** an effort. The orchestrator is whatever model
this session was launched with and is never selected.

## Step 3: Pair the reviewer against the implementer

Claude-written code (any tier) and your own code go to **Codex**; Codex-written
code goes to **Claude** in a fresh context. The table, the degraded form and
the review tier (which model and effort) are in `review.md`, their single
authority — this skill picks neither model nor effort.

Invoke `delegate-review` before declaring any non-trivial change complete,
regardless of who wrote it. Skip only for genuinely trivial changes — a typo, a
one-line config edit — where the round trip costs more than the change.

**Invoke it unconditionally rather than reasoning about whether a review already
happened.** `delegate-review` Step 0 keys on the diff hash, so a second mandate
firing on an unchanged diff reports the existing verified result instead of
dispatching a reviewer. This is what stops the independent review mandates from
stacking into several round trips on one diff.

The reviewer gets the diff, the goal and the acceptance criteria. Never the
implementer's report.

## Step 4: Reconcile

Combine your own assessment with the review's verified findings into **one**
report. Reconciling them is your job, not the user's.

Where the review and the implementer's self-report disagree, surface that
explicitly. That gap is why they were run blind.

Re-run the verification commands yourself. `tests_run` is evidence submitted,
never evidence accepted.

## Superpowers translation

Superpowers' execution skills hardcode Claude-shaped dispatch. Those
instructions describe a **role, not a mechanism**. Superpowers' own priority
order — user instructions outrank skills — is what authorises this translation.

| Superpowers says | Do this |
|---|---|
| "dispatch an implementer subagent" | `delegate-implement`, routed per Step 2 |
| "dispatch a reviewer subagent" | `delegate-review`, paired per Step 3 |
| `requesting-code-review` | `delegate-review`, same pairing |
| `dispatching-parallel-agents` | Multiple `delegate-implement`; a Codex pane and Claude subagents can run concurrently |
| `executing-plans`, `subagent-driven-development` | Route each task through this skill first |
| `verification-before-completion` | Re-run verification yourself; the report's `tests_run` is a claim |

Superpowers' prompt templates still apply: a Codex pane needs the same
self-contained brief a Claude subagent does, and more, since it shares none of
the conversation's context.
