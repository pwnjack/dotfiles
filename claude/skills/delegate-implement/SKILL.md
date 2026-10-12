---
name: delegate-implement
description: Use when implementation work should go to a subagent rather than being done inline - a Codex pane, a Claude pane, or an in-process Agent. Handles executor selection, the brief, the report-file handoff, and independent verification. Invoked by auto-subagent-routing, and by the /codex-implement and /claude-implement aliases.
---

# Delegate Implement

One implementation path for every executor. Read
`~/.claude/skills/_shared/handoff.md` first — it owns the brief template, the
report schema, the capability probe, pane mechanics and the model-selection
rules. This file owns only the workflow.

**Announce at start:** "Using delegate-implement to hand this to \<executor\>."

## Inputs

| Input | Values |
|---|---|
| Executor | `codex` \| `claude-pane` \| `agent-tool` |
| Capability tier | Claude alias, or Codex alias **plus** reasoning effort |

`auto-subagent-routing` normally supplies both. When invoked directly through an
alias, the alias names the executor and you pick the tier from the task shape.

## Step 1: Probe capability

Run **both** probes from the shared contract. They are separate axes:
mechanism (can I drive a pane?) and reviewer availability (is Codex usable?);
Codex runs only in a Herdr pane, so it needs both.
Probe the `herdr` command itself, not just `$HERDR_ENV` — the variable can be
set while the binary or session is gone.

If the requested executor is unavailable, fall back rather than failing, and say
once which mechanism actually ran.

## Step 2: Get a worker

**Pane (axis 1 passes):** `P=$(~/.claude/skills/_shared/herdr-spawn.sh codex <alias> <effort> <slug>)`
or `… claude <alias> <slug>`. It owns placement, the depth env var, the launch
argv (Codex: the alias resolved to `-m <slug>` plus effort; Claude: alias plus
the leaf directive) and the first-run check — see **Launching a worker** in the shared contract for its
exit codes. Exit `3` means Herdr is unusable: take the native path below.

A working agent belongs in the main tab where the user can watch it. It is
closed at Step 8, when this skill is finished with it — not the moment the
waiter returns, since the steps below may still read from it.

**Native `Agent` (axis 1 fails):** use the `Agent` tool with the matching
`model` alias. No pane, so no env var and no system-prompt injection — **the
brief's leaf marker is the only guard on this path**, and its backstop in
`CLAUDE.md` keys off that same marker rather than being independent of it. Never
omit the marker here, and never write a brief that itself asks for a subagent.

## Step 3: Write the brief

Use the template from the shared contract. Fill every section; a brief missing
its acceptance criteria produces work you cannot check, and one missing its
verification commands produces work you have to re-derive how to test.

The worker shares none of this conversation. State the goal, the paths you
already know, and the constraints that actually bear on this task — do not
gesture at context it cannot see.

Hand off: write the brief to `/tmp/codex-handoff/<slug>-<ts>.brief.md`
(`herdr-spawn.sh` already created the directory on the pane path), prompt the pane with a one-line pointer to it,
then start the waiter **with `run_in_background: true`**:

```bash
herdr agent prompt "$P" "Read the brief at /tmp/codex-handoff/<slug>-<ts>.brief.md and follow it exactly."
~/.claude/skills/_shared/herdr-await.sh "$P" /tmp/codex-handoff/<slug>-<ts>.json   # background
```

You are re-invoked when the waiter exits. Until then, do other useful work or
end the turn with a one-line status — never block on or poll the worker.

## Step 4: Handle the outcome

Act on the waiter's verdict per the table in the shared contract's **Dispatch
and wait** section: `REPORT` continue, `BLOCKED` resolve or surface, `NOREPORT`
re-prompt once, `QUOTA` flip axis 2 and re-route, `GONE`/`TIMEOUT` report rather
than retry silently. After any re-prompt, restart the waiter in the background.

## Step 5: Read the report file

```bash
jq . /tmp/codex-handoff/<slug>-<timestamp>.json
```

The file is the channel. If it is missing, follow the shared contract's
re-prompt-then-fall-back procedure, and say plainly that the result was scraped.

## Step 6: Verify independently

```bash
git status
git diff
```

Read the actual diff against the original goal and this repo's conventions.
Then **re-run the verification commands yourself.** The worker's `tests_run` is
a claim; your own run is evidence. A subagent being "another Claude" is no
reason to trust it more than Codex.

## Step 7: Hand off to review

Non-trivial changes go to `delegate-review`, which pairs the reviewer against
whoever implemented and picks the tier (`~/.claude/skills/_shared/review.md`).

`delegate-review` Step 0 deduplicates by diff hash, so invoking it here is cheap
even if another mandate already reviewed this exact diff — it will report the
existing result instead of dispatching. Invoke it rather than reasoning about
whether a review already happened; the marker is what knows.

**Pass the reviewer the diff, the goal and the acceptance criteria — never the
implementer's report** (*Blindness rule*, `review.md`).

## Step 8: Report

Tell the user what changed, your own assessment including anything you would
want fixed, which tier ran (for Codex, the model and effort the spawn printed), and that nothing has been committed. Staging and
committing stay separate and explicit.

**If the worker ran in a Herdr pane**, close it now: `herdr pane close "$P"`
(shared contract, Rule 2). This is the single close point for an implementation
delegation, and it applies on failure paths too. Every step above may still need
to read from the pane, which is why it happens here rather than when the waiter
returned.

On the native `Agent` path there is no pane, so skip this entirely rather than
running pane commands at the moment the pane mechanism was unavailable.
