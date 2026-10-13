---
name: delegate
description: Hand implementation, review or exploration to another model (Claude or Codex, each in a visible Herdr pane) and get a cross-family review of non-trivial changes. Use for "have codex/sonnet do X", "get codex to review this", /delegate, and before reporting a non-trivial change done.
---

# Delegate

## Choosing the worker: family, model, effort

Model and effort are one decision. The model sets the ceiling (what it can
understand at all); effort sets how much of that ceiling it uses. Pick the
model by the hardest part of the task, then the effort that model needs to do
it reliably:

| Work (implementing or reviewing) | Claude | Codex |
|---|---|---|
| Mechanical edits, read-only search | `haiku` · `medium` | `luna` · `medium` |
| Small, fully specified change | `haiku` · `high` | `luna` · `high` |
| Standard implementation; routine review | `sonnet` · `medium` | `sol` · `medium` |
| Tricky logic; substantial review | `sonnet` · `high` | `sol` · `high` |
| Subtle, security-bearing, cross-cutting, this harness | `opus` · `high` (`xhigh` if needed) | `sol` · `xhigh` |

- A lighter model is already the saving: never pair it with low effort.
  `low` is not used for delegated work.
- Raise effort while the task is within the model's reach; move up a model
  when it needs understanding the model lacks. Effort cannot buy capability.
- Codex when the spec is self-contained: it needs none of this conversation,
  and it spends Codex's quota instead of Claude's. Claude when the work needs
  this conversation's context or judgement about the repo's conventions.
- Do trivial work (a line, a rename, a config tweak) and ambiguous or
  architectural work yourself. A model or effort the user names wins.
- Only `haiku`, `sonnet`, `opus` and `luna`, `terra`, `sol` run freely. Any
  other name (`fable`, `astra`, anything new) runs only when the user asks
  for it by name, and `pane.sh` refuses it without `DELEGATE_EXPENSIVE=1`.
  Never `max`, and never `ultra` (it lets Codex delegate).

## Review

Before reporting a non-trivial change done, get one review from the other
family, with the row chosen from the table by the diff: Claude's work (yours
included) goes to Codex, Codex's to Claude. With no usable Codex, a different
Claude model reviews (`opus` for Sonnet's work, `sonnet` for yours or Opus's);
say the review was same-family.

The reviewer gets the goal, the acceptance criteria and what to review, never
the implementer's report or test claims:

- uncommitted work: `git diff HEAD`, plus `git status --short` for new files
- a commit: `git show <sha>`; a branch: `git diff main...<branch>`

Tell it: "Report findings only; do not edit any file. For each: file, line,
what is wrong, why it matters." Check every finding against the code yourself,
drop what does not hold, and give the user one report that merges the verified
findings with your own assessment.

## The brief

Workers share none of this conversation. Every brief:

```
[LEAF WORKER — DO NOT DELEGATE]
## Goal          what must be true when done
## Context       repo path, relevant files, constraints; read the repo's AGENTS.md/CLAUDE.md
## Out of scope  what not to touch
## Acceptance criteria
## Verification  exact commands and expected output
```

## Running a worker

Inside Herdr (`HERDR_ENV=1`) every worker, Claude or Codex, implementer,
reviewer or read-only explorer, runs in a visible pane; never the Agent tool.
Write the brief to `/tmp/delegate/<slug>.brief.md`, then with
`run_in_background: true`:

```bash
~/.claude/skills/delegate/pane.sh claude <alias> <effort> <slug> /tmp/delegate/<slug>.brief.md
~/.claude/skills/delegate/pane.sh codex <alias> <effort> <slug> /tmp/delegate/<slug>.brief.md
```

The slug is `a-z0-9-` and short (`dlg-<kind>-<slug>` fits 32 characters). The
script opens a pane beside you, hands over the brief, asks for a JSON report,
and exits with one verdict line (meanings in the script header):

- `REPORT`: the report is printed; `jq . <report>` for the rest.
- `BLOCKED`: answer with `herdr agent prompt <pane> "..."` when the answer is
  unambiguous, otherwise ask the user; then rerun with `--wait <pane> <report>`.
- `NOREPORT`: prompt once for the report only, then `--wait`.
- `QUOTA`: that family is out for the rest of the session; re-route.
- `NOSTART`, `GONE`, `TIMEOUT`: read the printed screen and report; do not
  silently retry.
- `NOHERDR`: not in a Herdr session (never returned inside one). Claude
  workers fall back to the Agent tool (`model`
  set to the alias, `run_in_background: true`); Codex is unavailable, so say so
  once and take the Claude route.

Close any pane the script left open with `herdr pane close <pane>` once you are
done with it. Report the model and effort from the verdict line.

## After any worker

Read the diff and re-run the verification commands yourself: a worker's
`tests_run` is a claim, not evidence. Nothing is committed unless the user asks.

## Superpowers

Its skills name the Agent tool; "dispatch a subagent" is a role, and inside
Herdr each one runs through `pane.sh` (a hook refuses the Agent tool there).
Its tiers map onto the table: cheap is the first two rows, standard the middle
two, most capable the last.

- **Which executor.** Subagent-driven development pays an implementer, a
  review and re-reviews per task; use it for plans with several substantial
  tasks. A small plan runs inline (`executing-plans`) with the one blind
  review from the other family at the end.
- **Briefs.** Never write or edit one by hand: `sdd-brief.sh` (run from the
  worktree; usage in its header) fills SDD's own templates and prints the
  path for `pane.sh`. Review briefs are blind by construction; exit 4 means
  the plugin's template changed and the script needs updating.
- **Workspace.** A worktree (`using-git-worktrees`): the implementer brief
  tells the worker to commit there, the one case a Codex leaf commits.
- **Implementer.** Its JSON `summary` starts with SDD's status word. Every
  `pane.sh` call for it carries `DELEGATE_KEEP=1`, `--wait` after a question
  included, so the pane survives for fix rounds.
- **Fix rounds.** 1-3: write the findings to a file, then
  `pane.sh --resume <pane> <file>` (a fresh report path, pane kept). 4-5: a
  fresh pane one row higher. Close the pane when the task review passes.
- **Reviewers.** Task review and re-review: the other family from that task's
  implementer. Final review: the other family to the implementers, on the
  whole branch; this is the review above, reported once. Keep a plan's
  implementers to one family; if both implemented, each family reviews it.
- `requesting-code-review` is the review above; `dispatching-parallel-agents`
  is one pane per agent. Never nest an orchestrator: workers are leaves.
