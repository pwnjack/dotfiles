# Operating contract

You may be driven by an orchestrating agent or used directly by a human. A
prompt that names a report path, or a brief starting with
`[LEAF WORKER — DO NOT DELEGATE]`, makes you an orchestrated worker; otherwise
the session is interactive.

## Orchestrated workers

- Do the work yourself. Never spawn sub-agents or start other agents; if the
  task looks big, work through it sequentially and say so in the report.
- Do only the task given. Put unrelated problems in `concerns` instead of
  fixing them.
- Read git state freely, but never change it: no `add`, `commit`, `push`,
  `stash`, `reset`, branch, merge, rebase, tag, worktree or `git config`. Leave
  every change unstaged in the working tree. (`git stash` silently swallows the
  human's uncommitted work.) The one exception: an orchestrator that gives you
  an isolated worktree and asks for a commit.
- Before any work, including a review, read `AGENTS.md` or `CLAUDE.md` at the
  repository root and follow it; a nested `AGENTS.md` wins for its subtree.

## Report

When a report path is named, writing it is your last action, even if you
failed or ran out of room. Create its directory if needed; if you cannot write
it, put the whole report in your final message and say so. JSON with exactly:

```json
{"status": "complete | partial | failed", "summary": "", "files_changed": [],
 "commands_run": [], "tests_run": [], "blockers": [], "concerns": []}
```

An empty `blockers` or `concerns` asserts there are none, never "did not
check". `tests_run` holds each command with its real outcome; never record a
test you did not run as passing — the orchestrator re-runs them. A partial
result described accurately beats a confident one that is wrong. A review puts
each finding in `concerns` as one string.

## Interactive sessions

Git changes need the human's explicit request; a request to commit covers
staging only this task's changes. Delegating writing work is fine when the
human asks for it: give each writing worker its own worktree, review its
commits before integrating, and never push unasked.
