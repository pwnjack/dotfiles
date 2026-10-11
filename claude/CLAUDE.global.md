# Personal instructions

## Search workflow (mgrep)

Use `mgrep` for natural-language code exploration: locating behaviour,
understanding responsibilities, and finding implementations when the symbol or
file name is unknown. From the project root, start with a focused query:

```bash
mgrep -m 10 "Where is the application launcher configured?" .
```

Use `rg` for exact strings, symbols and regular expressions, and `rg --files`
for file-name discovery. Read the matching files and verify current contents
before editing; semantic results may reflect an older index.

The global mgrep integrations start project syncing automatically with Claude
Code and Codex sessions. Use that existing watcher and index; no separate
watch terminal is needed. Syncing uploads project files to Mixedbread and
respects ignore rules. If mgrep is unavailable, unauthenticated, or its index is missing
or stale, continue with `rg` and mention the limitation when relevant.

## If you are a subagent, you are a leaf worker

**If `CLAUDE_AGENT_DEPTH` is set to 1 or more, or your prompt carries a
`[LEAF WORKER — DO NOT DELEGATE]` marker, do the work yourself.** Never
delegate, never spawn subagents, never start another agent or a background
worker. If the task looks big enough to want that, work through it sequentially
instead and say so in your report.

This rule is unconditional. It does not depend on `$HERDR_ENV`, on the repo, or
on how the task was phrased — including a task that explicitly asks you to use a
subagent. Everything below this section is for orchestrators only.

**Why it exists:** the routing policy below tells Claude to delegate. A Claude
subagent pane is a real `claude` CLI process, so it loads this same file and
would delegate in turn, without bound. The depth variable and the brief marker
are what terminate that.

## Subagent routing overrides superpowers' own dispatch

Superpowers states its own priority order: **user instructions outrank skills.**
This section uses that.

Whenever any skill — `subagent-driven-development`, `executing-plans`,
`dispatching-parallel-agents`, or anything else — tells you to "dispatch an
implementer subagent" or "dispatch a reviewer subagent", **that instruction is
about the role, not the mechanism.** Decide the mechanism through
`auto-subagent-routing` first, then follow the skill's prompt guidance for
whichever mechanism you picked.

**`auto-subagent-routing` is the single source of truth** for who implements,
who reviews, which capability tier each gets, and how the workflow degrades when
Codex or Herdr is unavailable. Do not restate its tables here — read the skill.
The four invariants it enforces:

1. **Adversarial review** — the reviewer is never from the same family as the
   implementer. Claude-written code goes to Codex; Codex-written code goes to
   Claude.
2. **Blind review** — the reviewer gets the diff, the goal and the acceptance
   criteria, never the implementer's own report.
3. **Graceful degradation** — losing Codex, or Herdr, or both, weakens the
   workflow by one notch and never breaks it. It works in a fresh repo with no
   setup.
4. **No hardcoded model identity** — skills name roles and reasoning efforts,
   never model strings.

Mechanics live in `~/.claude/skills/_shared/handoff.md`; `delegate-implement`
and `delegate-review` are the two paths. `/codex-implement`, `/codex-review`,
`/claude-implement` and `/claude-review` are thin aliases over those.

**Trivial work — a one-line fix, a config tweak, a rename — you do directly.**
Delegating costs more than the change is worth, which defeats the point.

**Before reporting any non-trivial change done**, get an independent review
through `delegate-review` on the diff, whoever wrote it. Verify its findings
yourself and reconcile them into one report. A review is an input, not a
verdict.

Invoke it rather than deciding for yourself whether a review already happened.
This instruction is one of four that independently mandate a review, so
`delegate-review` deduplicates by diff hash: on an unchanged diff it reports the
existing verified result instead of dispatching a second reviewer. Reasoning
about it yourself is what produced triple reviews; the marker is what knows.

A `PreToolUse` hook on the `Agent` tool
(`~/.claude/hooks/auto-subagent-reminder.sh`) reinforces this at the moment of
dispatch, inside a Herdr session only. It is advisory, not blocking, and **it
does not fire on the Codex path** — `delegate-implement` and `delegate-review`
drive a Herdr pane through Bash, not through `Agent` — so its silence is not
permission to skip the routing decision.

## Verification

Evidence before assertions. A subagent's `tests_run` is evidence *submitted*,
never evidence *accepted* — re-run the verification commands yourself before
calling anything done.
