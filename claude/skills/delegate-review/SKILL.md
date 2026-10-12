---
name: delegate-review
description: Use when a diff needs review by an independent subagent - after any non-trivial change, whoever wrote it. Pairs the reviewer against the implementer's family, keeps the review blind to the implementer's own report, and verifies findings before relaying them. Invoked by auto-subagent-routing, and by the /codex-review and /claude-review aliases.
---

# Delegate Review

Read both shared files first. `~/.claude/skills/_shared/handoff.md` owns the
brief template, report schema, capability probe, pane mechanics and model
rules. `~/.claude/skills/_shared/review.md` owns the pairing table, the
blindness rule, review idempotency and the review tier. This file owns only the
workflow.

**Announce at start:** "Using delegate-review to get an independent review from
\<reviewer\>."

## Inputs

| Input | Values |
|---|---|
| Reviewer family | `codex` \| `claude`, or chosen by the pairing rule |

`auto-subagent-routing` or an alias normally supplies it; the pairing rule
overrides a pinned family that would mean self-review.

## Two invariants

Both are defined in `review.md`. They come before any mechanics, and where
convenience conflicts with them, they win.

1. **Adversarial pairing.** Whenever both families are available the reviewer is
   never from the implementer's family: Claude-written code (or the
   orchestrator's) goes to Codex, Codex-written code to Claude in a fresh
   context. If an alias or the user names a reviewer that would violate this,
   the pairing wins and you say so. With no usable Codex the rule degrades to
   cross-model plus fresh context; announce it once and never present it as the
   full guarantee.
2. **Blind review.** The reviewer gets the raw diff, the original goal and the
   acceptance criteria, and nothing from the implementer's `summary`,
   `tests_run`, `blockers` or `concerns`. Those go only to you, for
   reconciliation. The gap between an uncontaminated review and the
   implementer's self-report is the highest-signal output of this workflow.

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

**Run this before anything else.** Several separate instructions each mandate a
review and none can see the others fire; this check is what stops one unchanged
diff being reviewed two or three times. See *Review idempotency* in `review.md`
for the payload snippet, the four traps it avoids and the marker format.

Determine the target first (Step 1's target selection feeds this). Then build
the payload once and key on it:

```bash
# TARGET empty = working tree; otherwise a commit / branch / range
#   -> writes $PAYLOAD and sets $DIFF_SHA
MARKER="/tmp/codex-handoff/reviewed-${DIFF_SHA}.json"
[ -f "$MARKER" ] && jq . "$MARKER"
```

**`$PAYLOAD` is both what you hash and what you send the reviewer.** Do not
rebuild, re-derive or re-diff it at Step 3 — a payload derived twice can differ
twice, and then the marker certifies something the reviewer never saw.

If the marker exists, **stop here.** Report its verified findings and say
"already reviewed at this diff state" — a suppressed review is announced, never
silent. Do not dispatch a reviewer. If it is absent, continue; you write the
marker in Step 6. Any working-tree edit changes `DIFF_SHA`, so a fix always
earns a fresh review.

## Step 1: Determine the target, the pairing and the tier

Default target is the uncommitted diff (staged plus unstaged). If the user names
a commit, branch or range, describe that target in the brief — the worker
receives text, not CLI flags.

Establish who implemented, then read the pairing off *Adversarial pairing* in
`review.md`. Check the diff against the dual-review list. Then read the
reviewing model and effort off *Review tier* in `review.md`, using the payload's
size — that table is the only authority on both. Codex `astra` and Claude
`fable` are never chosen here, only on the user's explicit request.

```bash
grep -c '^[+-][^+-]' "$PAYLOAD"
```

Measure from `$PAYLOAD`, never `git diff HEAD --shortstat` — `--shortstat`
reports nothing for untracked files, so a brand-new thousand-line file would
measure zero and be tiered "routine".

## Step 2: Get a reviewer

Spawn a fresh pane per `handoff.md` — `herdr-spawn.sh codex <alias> <effort> <slug>`
or `herdr-spawn.sh claude <alias> <slug>`, with the model from *Review tier* (or,
with no usable Codex, the degraded cross-model pairing). Panes are never reused, so a reviewer
structurally has no memory of having written the code. Exit `3` (no Herdr) means
the native `Agent` path.

Write the brief to a file, prompt the pane with a pointer to it, and start
`herdr-await.sh` with `run_in_background: true` (`handoff.md`, **Dispatch and
wait**). You are re-invoked on its verdict; do not block or poll.

## Step 3: Write the review brief

Use the template in `handoff.md`, with Context carrying **only** diff, goal and
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
  buys nothing. Verifying a claim means opening what the claim points at.
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
without another round trip. Write the findings **that survived Step 4**, as a
JSON array you construct yourself:

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
(`handoff.md`, Rule 2). Do this on failure paths too, so no finished reviewer
lingers in the tab.

Skip this on the native `Agent` path — there is no pane, and reaching for pane
commands is precisely wrong at the moment the pane mechanism was unavailable.
