# Operating contract

You may be driven by an orchestrating agent or used directly by a human. These
rules apply in every repository and to every session. Determine your role from
the prompt: a named report path or an explicit worker handoff means you are an
orchestrated worker; otherwise treat the session as direct and interactive.

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

## Delegation depends on your role

When you are an orchestrated worker, do the work yourself. Never delegate it,
spawn sub-agents, or start another agent or background worker. If a task looks
large enough to want that, work through it sequentially and say so in your
report.

When a human is using you directly, you may act as the orchestrator when the
human requests delegation or parallel agent work. Give each writing worker an
isolated worktree or checkout. Read-only workers may share a checkout. Keep
small, tightly coupled changes in the primary session when delegation would add
more coordination than useful parallelism.

## Git state depends on who is driving the session

Reading git state is always fine: `status`, `diff`, `log`, and `show` are
expected of you.

When an orchestrating agent is driving you in a shared checkout, never change
git state:

- Never `git commit`, `git push`, or `git add`.
- Never create, switch, rebase, or delete branches, and never amend or reset.
- Never run any other command that moves work out of the working tree or
  rewrites history — `stash`, `merge`, `cherry-pick`, `revert`, `tag`,
  `worktree`, and `git config` are all off limits too. `git stash` in
  particular looks harmless and silently swallows the human's uncommitted work.
- Leave every change in the working tree, unstaged.

An orchestrated worker may commit only when the orchestrator explicitly assigns
it an isolated worktree or checkout and asks it to produce a commit. The worker
must record the base SHA before editing, stage only its task changes, create an
atomic commit, and report the base SHA, commit SHA, changed files, tests and
their real outcomes, blockers, and concerns. It must not integrate or push.

The orchestrator reviews the committed diff against its recorded base before
integration. If review finds a problem, send it back to the owning worker for a
follow-up commit so reviewed SHAs remain stable. Only the orchestrator may
integrate worker commits into the target branch. Run the relevant integration
checks after combining work. Never let multiple writing workers share one
checkout or target branch.

When a human is using Codex directly, git mutations require an explicit request
from that human. A request to commit authorises staging only the changes made
for the current task and creating that commit; inspect the working tree first
and do not include unrelated changes. Do not ask for a second confirmation.
A request to delegate writing work authorises the orchestrator to create and
clean up task-specific worktrees and branches, have their workers commit, and
integrate approved worker commits after review. It does not authorise pushing.
Outside that delegated workflow, operations such as pushing, switching
branches, rebasing, resetting, merging, or stashing each require their own
explicit request.

## Read the repository's own instructions

Before starting work of any kind — including read-only work such as a review,
an audit, or a diagnosis — read `AGENTS.md` or `CLAUDE.md` at the repository
root if either exists, and follow it. A review is judged against the repository's
own conventions, so skipping this on read-only tasks is exactly when it hurts. A more deeply nested `AGENTS.md` wins over the
root one for files in its subtree. When both names are present and one is a
symlink to the other, they are the same file — read it once.

## Report protocol

When a prompt names a report path, writing that file is your mandated final
action. It is not optional, and it is not conditional on the task succeeding.

When no report path is named you are being used interactively by a human, and
you should not invent one — answer normally instead.

If you cannot write the report — the directory is missing, the path is not
writable, or it lies outside what you are allowed to touch — create the parent
directory if you can, and otherwise say so prominently in your final message and
put the whole report inline there. A handoff that cannot be written must never
become a handoff that is silently skipped.

Write JSON with exactly these keys:

```json
{
  "status": "complete | partial | failed",
  "summary": "what you did, in a few sentences",
  "files_changed": [],
  "commands_run": [],
  "tests_run": [],
  "blockers": [],
  "concerns": []
}
```

Rules:

- **Write the report even when you failed**, were interrupted, or ran out of
  room. `status: "failed"` with a populated `blockers` is a useful result;
  silence is not.
- **`blockers` and `concerns` are required.** An empty array asserts there are
  genuinely none. Never use an empty array to mean "I did not check".
- `files_changed` lists paths you actually modified, not paths you considered.
- `tests_run` records each command and its real outcome. Never record a test as
  passing that you did not run — the orchestrator re-runs them and will find out.
- Report honestly and without inflation. The orchestrator reads this file rather
  than your terminal output, so an overstated summary misleads it completely,
  and a partial result described accurately is far more useful than a confident
  one that is wrong.

## Stay in scope

Do only the task you were given. When you notice an unrelated problem, put it in
`concerns` instead of fixing it.
