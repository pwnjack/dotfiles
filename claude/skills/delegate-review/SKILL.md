---
name: delegate-review
description: Use when a diff needs review by an independent subagent - after any non-trivial change, whoever wrote it. Pairs the reviewer against the implementer's family, keeps the review blind to the implementer's own report, and verifies findings before relaying them. Invoked by auto-subagent-routing, and by the /codex-review and /claude-review aliases.
---

# Delegate Review

Read `~/.claude/skills/_shared/handoff.md` first — it owns the brief template,
report schema, capability probe, pane mechanics and model rules.

**Announce at start:** "Using delegate-review to get an independent review from
\<reviewer\>."

## Inputs

| Input | Values |
|---|---|
| Reviewer family | `codex` \| `claude`, or chosen by the pairing rule below |

`auto-subagent-routing` or an alias normally supplies it; the pairing rule
overrides a pinned family that would mean self-review.

## Two invariants

These come before any mechanics. Where convenience conflicts with them,
they win.

### 1. Adversarial pairing

**Whenever both families are available, the reviewer is never from the same
family as the implementer.** That conditional is load-bearing and is stated
honestly here: when Codex is unavailable there is only one family left, so the
guarantee cannot hold and degrades to the weaker rule below. Never describe the
degraded form as though it were the full guarantee.

| Implementer | Reviewer |
|---|---|
| Claude, any tier | **Codex** |
| **Codex** | **Claude**, fresh context |
| The orchestrator itself | **Codex** |

**This table picks the family only. It does not set effort or which model
reviews** — *Review tier* in the shared contract is the single authority on
both, keyed to the size of the payload and whether a trigger
path is touched. Naming a value here as well would give an LLM two instructions
that both claim authority and licence to pick either, which defeats the point of
scaling effort at all.

This makes same-family self-review structurally impossible rather than merely
discouraged. **If an alias or the user names an executor that would violate the
pairing, the pairing wins — and say so rather than silently overriding.**

When there is no usable Codex — axis 2 fails, or axis 1 does, since Codex runs
only in a Herdr pane — the rule degrades to cross-**model** plus
fresh context: `opus` reviews Sonnet's work, `sonnet` reviews Opus's. This is
same-family review and is genuinely weaker — an independent *context* and a
different *tier*, but not an independent vendor. Announce it once, and say which
form you got when reporting.

### 2. Blind review

The reviewer receives exactly three things:

1. the raw diff
2. the original goal
3. the acceptance criteria from the original brief

**Never pass the implementer's `summary`, `tests_run`, `blockers` or
`concerns` into a review brief.** Those go only to you, for reconciliation.

A reviewer told "the implementer was worried about X" will find X and stop
looking. The disagreement between an uncontaminated review and the implementer's
self-report is the highest-signal output of this workflow, and it exists only if
the two were blind to each other.

## Dual review

Single adversarial review by default. **Both** families review when the diff
touches any of:

- authentication, secrets, crypto, or permissions
- database migrations or schema changes
- destructive operations (`rm -rf`, `DROP`, force-push, bulk delete)
- public API or config contracts that other things depend on
- the delegation workflow itself

The list is enumerated rather than described as "high-risk" on purpose: a
judgement call is something you can rationalise away at the end of a long task,
whereas a matching path in the diff is checkable. When both review, reconcile
them into one report — do not hand the user two opinions to merge themselves.

**When only one family is available**, dual review cannot be satisfied as
written. Do not silently drop to a single review. Instead run two passes that
are independent in every way still open to you — separate fresh sessions, and
different capability tiers — then tell the user the dual-review requirement was
met in degraded form and which axis was unavailable. A trigger on this list is
exactly when the user needs to know the guarantee was weaker than usual.

## Step 0: Has this exact diff already been reviewed?

**Run this before anything else.** Four separate instructions each mandate a
review and none can see the others fire; without this check a single unchanged
diff gets reviewed two or three times. See *Review idempotency* in the shared
contract.

Determine the target first — Step 1's target selection feeds this, so read it
before running anything here. Then build the payload and key on it, using the
snippet in *Review idempotency* in the shared contract:

```bash
# TARGET empty = working tree; otherwise a commit / branch / range
#   -> writes $PAYLOAD and sets $DIFF_SHA
MARKER="/tmp/codex-handoff/reviewed-${DIFF_SHA}.json"
[ -f "$MARKER" ] && jq . "$MARKER"
```

**`$PAYLOAD` is both what you hash and what you send the reviewer.** Do not
rebuild, re-derive or re-diff it at Step 3 — a payload derived twice can differ
twice, and then the marker certifies something the reviewer never saw. Build it
once, here.

The shared contract explains the four traps this shape avoids: keying on the
working tree while reviewing a named commit, untracked files reaching the hash
but not the reviewer, `xargs sha256sum` treating a file named `--help` as a
flag, and `git status --porcelain` not being a content hash.

If the marker exists, **stop here.** Report its verified findings and say
"already reviewed at this diff state" — a suppressed review is announced, never
silent. Do not dispatch a reviewer.

If it is absent, continue. You will write the marker in Step 5.

Any working-tree edit changes `DIFF_SHA`, so a fix always earns a fresh review
with no invalidation logic to maintain.

## Step 1: Determine the target, the pairing and the tier

Default target is the uncommitted diff (staged plus unstaged). If the user names
a commit, branch or range, describe that target in the brief — the worker
receives text, not CLI flags.

Establish who implemented, then read the pairing off the table. Check the diff
against the dual-review list.

Then read the reviewing model and effort off *Review tier* in the shared
contract, using the payload's size — **that table is the only authority on
both**, so it is not restated here. Codex `astra` and Claude `fable` are never
chosen here — only on the user's explicit request. The cross-family guarantee holds at every tier: effort is the
dial, not whether an independent family looks at all.

```bash
grep -c '^[+-][^+-]' "$PAYLOAD"
```

Measure from `$PAYLOAD`, never `git diff HEAD --shortstat` — `--shortstat`
reports nothing for untracked files, so a brand-new thousand-line file would
measure zero and be tiered "routine".

## Step 2: Get a reviewer

Spawn a fresh pane per the shared contract — `herdr-spawn.sh codex <alias> <effort> <slug>`
or `herdr-spawn.sh claude <alias> <slug>`, with the model from *Review tier* (or,
with no usable Codex, the degraded cross-model pairing). Panes are never reused, so a reviewer
structurally has no memory of having written the code. Exit `3` (no Herdr) means
the native `Agent` path.

Write the brief to a file, prompt the pane with a pointer to it, and start
`herdr-await.sh` with `run_in_background: true` (shared contract, **Dispatch and
wait**). You are re-invoked on its verdict; do not block or poll.

## Step 3: Write the review brief

Use the shared template, with Context carrying **only** diff, goal and
acceptance criteria. Point the reviewer at `$PAYLOAD` — the file built in Step 0
— rather than describing a command for it to re-derive the diff itself. That
file is what `$DIFF_SHA` covers, so sending anything else breaks the guarantee
that the marker describes what was actually reviewed.

Ask for findings as text plus a report file, and state that nothing may be
edited:

```
Report findings only — do not edit any file.
For each finding: file, line if applicable, what is wrong, and why it matters.
```

Before sending, re-read your own brief and confirm no field from the
implementer's report leaked into it.

## Step 4: Verify before relaying

Read the report file, then **check every finding against the actual code.**

- Open the file and line. Confirm the claim is real and not hallucinated.
- Drop whatever does not hold up.
- **Scope this to the lines the review named.** `delegate-implement` Step 6
  already read the diff as a whole against the goal; re-reading all of it here
  buys nothing and is one of the duplicated passes this workflow was spending
  tokens on. Verifying a claim means opening what the claim points at.
- Do not hedge with "the reviewer thinks maybe" on something you have verified.
  Either it is a real issue — state it directly — or it is not, and you do not
  mention it.

A review is an input, not a verdict. This applies identically whether Codex or
Claude produced it.

## Step 5: Report

Present only verified findings, most important first. Where the review and the
implementer's self-report disagree, say so explicitly — that gap is the point of
running them blind.

If nothing survived verification, say that plainly rather than padding.

## Step 6: Record the review, then close the pane

Write the marker so the remaining mandates for this same diff are satisfied
without another round trip:

Write the findings **that survived Step 4**, as a JSON array you construct
yourself:

```bash
mkdir -p /tmp/codex-handoff
VERIFIED='["<finding you confirmed>", "..."]'   # [] if none survived

jq -n --arg sha "$DIFF_SHA" --arg fam "<reviewer family>" --arg tier "<codex alias>/<effort>, or the claude alias" \
      --argjson findings "$VERIFIED" \
  '{diff_sha:$sha, reviewer:$fam, tier:$tier, verified_findings:$findings}' \
  > "/tmp/codex-handoff/reviewed-${DIFF_SHA}.json"
```

**Never pipe the reviewer's raw `.concerns` into this file.** Step 4 exists to
drop findings that do not hold up; copying the raw array puts every dropped
hallucination back, labelled `verified_findings`, and the next cache hit relays
it as confirmed. The marker stands in for a completed review, so it carries the
same standard as one.

Then, **if the reviewer ran in a Herdr pane**, close it: `herdr pane close "$P"`
(shared contract, Rule 2). Do this on failure paths too, so no finished
reviewer lingers in the tab.

Skip this on the native `Agent` path — there is no pane, and reaching for pane
commands is precisely wrong at the moment the pane mechanism was unavailable.
