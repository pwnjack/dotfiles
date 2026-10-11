---
name: auto-subagent-routing
description: Use at the start of any implementation or code-review task, and before declaring any code change complete, to decide who does the work and who reviews it. Picks executor and capability tier, pairs the reviewer adversarially against the implementer, and degrades gracefully when Codex or Herdr is unavailable. Governs when to use delegate-implement and delegate-review.
---

# Auto Subagent Routing

Decides **who** does a piece of work and **who reviews it**.
`delegate-implement` and `delegate-review` define how each mechanism works; this
skill decides which to reach for. Mechanics live in
`~/.claude/skills/_shared/handoff.md`.

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

Two axes, not one ladder. They fail separately, but Codex runs only in a Herdr
pane, so cross-family review needs both to pass.

```bash
# Axis 1 — mechanism: can I actually drive a pane?
[ "${HERDR_ENV:-}" = "1" ] && command -v herdr >/dev/null 2>&1 && herdr agent list >/dev/null 2>&1

# Axis 2 — reviewer: is Codex usable?
command -v codex >/dev/null 2>&1 && codex login status >/dev/null 2>&1
```

| Axis 1 | Mechanism |
|---|---|
| pass | Herdr panes |
| fail | native `Agent` tool |

| Axis 2 | Review pairing |
|---|---|
| pass (and axis 1 passes) | Cross-**family** — the full guarantee |
| fail, or axis 1 fails | **Degraded:** cross-**model** + fresh context |

Cache both for the session. Probe the `herdr` command, not just `$HERDR_ENV`:
the variable can be set while the binary or session is gone, which would select
panes and then fail on the first command.

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
user's usage and run only when the user explicitly asks for them; see *Model
selection* in the shared contract.

## Step 3: Pair the reviewer against the implementer

| Implementer | Reviewer |
|---|---|
| Claude, any tier | **Codex** |
| Codex | **Claude**, fresh context |
| You | **Codex** |

This table picks the reviewing **family** only. Which model reviews — `sonnet`
or `opus`, and Codex's alias and effort — comes from *Review tier* in the shared
contract, their single authority; naming one here too would let an LLM choose
between two competing instructions.

Invoke `delegate-review` before declaring any non-trivial change complete,
regardless of who wrote it. Skip only for genuinely trivial changes — a typo, a
one-line config edit — where the round trip costs more than the change.

**Invoke it unconditionally rather than reasoning about whether a review already
happened.** `delegate-review` Step 0 keys on the diff hash, so a second mandate
firing on an unchanged diff reports the existing verified result instead of
dispatching a reviewer. This is what stops the four independent review mandates
from stacking into three round trips on one diff.

Review effort scales with the diff, per *Review tier* in the shared contract.
The cross-family guarantee holds at every tier; effort is the dial, not whether
an independent family looks at the code.

The reviewer gets the diff, the goal and the acceptance criteria. Never the
implementer's report.

## Step 4: Reconcile

Combine your own assessment with the review's verified findings into **one**
report. Reconciling them is your job, not the user's.

Where the review and the implementer's self-report disagree, surface that
explicitly. That gap is why they were run blind.

Re-run the verification commands yourself. `tests_run` is evidence submitted,
never evidence accepted.

## Model selection

No skill file contains a *pinned* model identifier — nothing of the form
`claude-<name>-<date>` or `gpt-<version>-<codename>`, which names one generation
and rots when it is superseded. Aliases are the opposite and are therefore
required: `sonnet` is a moving pointer, so writing it is what keeps the file
correct. Claude uses aliases (`opus`, `sonnet`, `haiku`, and `fable` only on the
user's explicit request), which always resolve to the current generation.
Codex has no aliases, so its **codenames** serve as them — `luna`, `terra`,
`sol`, and `astra` only on explicit request — each resolved by `herdr-spawn.sh`
to the newest listed model of that name at launch, plus `inherit` for the
user's `config.toml` model. Every Codex delegation names an alias *and* a
reasoning **effort**; both are stable across model generations in a way slugs
are not. The resolution rule and the alias table are in *Model selection* in the
shared contract.

**Effort `ultra` is forbidden everywhere** — it enables automatic task
delegation and would breach the recursion guard from inside a leaf worker.

The orchestrator is whatever model this session was launched with. It is never
selected and needs no detection.

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
