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

## Subagent routing

Whenever any skill (`subagent-driven-development`, `executing-plans`,
`dispatching-parallel-agents`, `requesting-code-review`, or anything else) tells
you to "dispatch an implementer subagent" or "dispatch a reviewer subagent",
**that is about the role, not the mechanism.** User instructions outrank skills,
so decide the mechanism through `auto-subagent-routing` first, then follow the
skill's prompt guidance for whichever mechanism you picked.

`auto-subagent-routing` is the single source of truth for who implements, who
reviews, which tier each gets and how the workflow degrades without Codex or
Herdr; do not restate its tables here. The two rules to hold even before you
load it: the reviewer is never from the same family as the implementer, and it
never sees the implementer's report. Mechanics are in
`~/.claude/skills/_shared/handoff.md` and `review.md`; `/codex-implement`,
`/codex-review`, `/claude-implement` and `/claude-review` are thin aliases over
`delegate-implement` and `delegate-review`.

**Trivial work — a one-line fix, a config tweak, a rename — you do directly.**
Delegating costs more than the change is worth.

**Before reporting any non-trivial change done**, get an independent review
through `delegate-review` on the diff, whoever wrote it. Verify its findings
yourself and reconcile them into one report; a review is an input, not a
verdict. Invoke it rather than deciding for yourself whether a review already
happened: it deduplicates by diff hash, so an unchanged diff reports the
existing verified result instead of dispatching a second reviewer.

A `PreToolUse` hook on the `Agent` tool (`~/.claude/hooks/auto-subagent-reminder.sh`)
reminds you at the moment of dispatch, inside a Herdr session only. It is
advisory and does not fire on the Codex path, which drives a Herdr pane through
Bash, so its silence is not permission to skip the routing decision.

## Verification

Evidence before assertions. A subagent's `tests_run` is evidence *submitted*,
never evidence *accepted* — re-run the verification commands yourself before
calling anything done.
