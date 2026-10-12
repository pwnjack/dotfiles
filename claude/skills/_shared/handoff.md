# Shared handoff contract

Reference file for `delegate-implement` and `delegate-review`. Not a skill —
this directory has no `SKILL.md` on purpose. Both delegate skills read this
instead of restating it, so the contract has exactly one copy. It covers
running a worker: probe, report, brief, models, guards, panes. What is specific
to reviews — pairing, blindness, idempotency, tier — is in `review.md`, which
only `delegate-review` and the review steps need to read.

## Capability probe

Two axes. They are not a single ladder: mechanism and reviewer availability
fail separately. But Codex runs only in a Herdr pane (`herdr-spawn.sh codex`
exits 3 without Herdr), so the cross-family pairing needs **both** to pass;
with axis 1 failing, review takes the degraded pairing whatever axis 2 says.
Probe both once per session and cache the answers. Never assume either.

```bash
# Axis 1 — mechanism: can I actually drive a pane?
[ "${HERDR_ENV:-}" = "1" ] && command -v herdr >/dev/null 2>&1 && herdr agent list >/dev/null 2>&1

# Axis 2 — reviewer: is Codex usable?
command -v codex >/dev/null 2>&1 && codex login status >/dev/null 2>&1
```

| Axis 1 — mechanism | Use |
|---|---|
| pass | Herdr panes |
| fail | native `Agent` tool |

| Axis 2 — Codex | Review pairing |
|---|---|
| pass (and axis 1 passes) | Cross-**family** — the full guarantee |
| fail, or axis 1 fails | **Degraded:** cross-**model** + fresh context (`opus` reviews Sonnet's work, `sonnet` reviews Opus's) |

`$HERDR_ENV` alone is not a mechanism probe — the variable can be set while the
binary or the session is gone, which selects panes and then fails on the first
command. Probe the command, not the variable.

**The axis-2 probe cannot detect an exhausted quota.** `codex login status`
reports "Logged in" whether or not any requests remain — verified against a live
quota exhaustion on 2026-08-02. So a pass means *installed and authenticated*,
never *usable right now*.

Quota is therefore detectable only on use. Any delegation that fails on auth or
quota flips axis 2 to fail for the rest of the session. Treat an in-flight
`usage limit` message as authoritative even when the worker's own report says
`complete` — the work may have finished just before the wall, and the next
delegation will not. Announce a degraded axis **once**, then carry on; never
stop to ask.

**Say plainly when review is degraded.** Cross-model review is still
same-family review, and it is weaker than the cross-family guarantee. Never
present it as though the full guarantee held.

## Report path

```
/tmp/codex-handoff/<slug>-<timestamp>.json
```

`<slug>` is a short kebab-case task name; `<timestamp>` is `date +%s`. Create the
directory before delegating. This path is deliberately outside the repo: it is
writable without a sandbox approval prompt, and it works on a fresh checkout of
a repo that has no ignore rule for it.

## Report schema

```json
{
  "status": "complete | partial | failed",
  "summary": "string",
  "files_changed": [],
  "commands_run": [],
  "tests_run": [],
  "blockers": [],
  "concerns": []
}
```

`blockers` and `concerns` are required; an empty array asserts genuinely none.
A review reports each finding as a separate string in `concerns`.

## Reading the report

The **file is the channel**. Scrollback is a diagnostic, not a source.

```bash
jq . /tmp/codex-handoff/<slug>-<timestamp>.json
```

If the file is absent:

1. Re-prompt the worker once, asking only for the report.
2. If it is still absent, recover by whichever channel the mechanism leaves you:
   - **Pane:** `herdr agent read <pane> --lines 200`.
   - **Native `Agent`:** the tool's own return value already *is* the report —
     there is no file to miss, so this path cannot reach step 2.
   - **Pane, with Herdr itself broken:** there is no recovery channel. Report
     the delegation as failed, say the worker's output was unrecoverable, and
     do not guess at what it did.
3. **Say explicitly which channel you used.** A scraped result must never be
   presented as though it were a structured one.

## Evidence rule

`tests_run` is evidence **submitted**, never evidence **accepted**. Re-run the
verification commands yourself before reporting anything as done. A worker
claiming its tests passed is a claim about the world, and claims get checked.

## Brief template

Every brief, for every executor, uses this shape. The marker is the recursion
guard's only layer that reaches in-process `Agent`-tool subagents, so it is
never omitted.

```
[LEAF WORKER — DO NOT DELEGATE]
Do the work yourself. Do not spawn subagents, delegate, or start other agents.

## Goal
<one paragraph: what must be true when you are done>

## Context
Repo: <absolute path>
Read AGENTS.md or CLAUDE.md at the repo root if either exists, and follow it.
Relevant files: <paths you already know about>
<constraints that matter for this task>

## Out of scope
<what not to touch; where to put unrelated problems instead>

## Acceptance criteria
- <checkable statement>
- <checkable statement>

## Verification
<exact commands to run, with expected output>

## Report
FINAL STEP (mandatory): write your report to <path> as JSON with exactly these
keys: status (complete|partial|failed), summary, files_changed, commands_run,
tests_run, blockers, concerns. Write it even if you failed.
```

Write briefs fully self-contained. A delegated worker shares none of this
conversation's context, and a Codex pane shares none of Claude's either.

## Model selection

**No skill file may contain a *pinned* model identifier** — no
`claude-<name>-<date>`, no `gpt-<version>-<codename>`. Those name one generation
and are wrong the day it is superseded.

Aliases are the opposite and are therefore **required**: `sonnet` is a moving
pointer to the current Sonnet, so writing it is what keeps the file correct
across generations. Codex has no aliases of its own, so its **codenames** play
the same part: `sol` means "the newest listed Sol", whatever generation that is.

| Side | Model dial | Effort dial |
|---|---|---|
| Claude | `haiku` / `sonnet` / `opus`; `fable` opt-in only | — |
| Codex | `luna` / `terra` / `sol`; `astra` opt-in only; `inherit` | `low` / `medium` / `high` / `xhigh` |

Every Codex delegation names **both** an alias and an effort, the way every
Claude delegation names an alias. Pick them separately — the model is how
capable, the effort is how hard it thinks — and pick the lightest model that
handles the task well:

| Codex alias | Claude analogue | Use for |
|---|---|---|
| `luna` | `haiku` | bulk mechanical edits |
| `terra` | — | small, well-specified, straightforward changes |
| `sol` | `sonnet` / `opus` | well-specified implementation, complex logic at `high`/`xhigh`, every Codex review |
| `astra` | `fable` | **only when the user explicitly asks for it** |
| `inherit` | — | only when the user asks for their `config.toml` model; also the automatic fallback below. Omits `-m` |

The alias list is not closed: any codename in the catalogue resolves the same
way, so a new line of model is usable by name the day it ships.

**`astra` and Claude `fable` are opt-in only.** They consume the user's usage
far faster than the models below them, so the user reserves them for explicit
requests ("use astra", "have fable do it"). Never pick either from a routing
table, a review tier, or your own judgement that a task is hard — reach for
`sol` at `high`/`xhigh`, or Claude `opus`, instead. `herdr-spawn.sh` refuses
both (exit 2) unless the command sets `DELEGATE_EXPENSIVE=1`; set it only on a
spawn the user asked for. The native `Agent` path has no such gate, so the rule
there is this paragraph alone.

Resolution happens **at launch**, from `~/.codex/models_cache.json`, in
`codex-model.sh` (which `herdr-spawn.sh` calls — do not resolve by hand; its
header is the full rule):

- **Newest of that name.** Among listed models whose codename is the alias, the
  highest generation version wins; the plain `<generation>-<alias>` slug beats
  `-mini`/`-pro` variants and dated snapshots. A codename the newest generation
  lacks resolves to the newest one that has it, and moves up on its own once a
  newer one ships.
- **The gate follows the launched model.** Before any pane exists, the spawn
  asks `codex-model.sh --is-expensive` about both the alias and the model that
  would actually run — for `inherit` and the fallback, the one `config.toml`
  selects, read with a real TOML parser, profile included. The check is by
  codename against `EXPENSIVE` in that script and needs no catalogue, so a
  broken catalogue cannot open the gate. A launch whose model cannot be
  determined is refused. **When Codex ships a new flagship codename, add it to
  `EXPENSIVE`** — an automatic guess from priority was tried and misfired in
  both directions.
- **Degrades, never fails.** A codename no listed model has, or a missing,
  unreadable or empty catalogue, degrades to `inherit` with the reason on
  stderr. The spawn prints the model that actually launched — report it.
- **Effort** is clamped down to the highest level the model lists, else up to
  its lowest; a model that lists none gets the request unchanged.

`~/.codex/config.toml`'s `model` is the user's choice for **interactive** Codex
and for `inherit`; delegates do not read it otherwise. A `QUOTA` verdict flips
axis 2 as before, whichever model hit it — do not quietly retry on a lighter
model, since whether quota is per-model has not been measured.

**Reasoning effort `ultra` is forbidden everywhere.** It enables automatic task
delegation and would breach the recursion guard from inside a leaf worker.

## Recursion guards: what actually covers what

Three guards exist, but **no single mechanism carries all three.** Know which
one you are relying on rather than assuming defence in depth everywhere.

| Mechanism | `CLAUDE_AGENT_DEPTH` | System-prompt injection | Brief marker | Standing contract |
|---|---|---|---|---|
| Claude pane | yes, via `--env` | yes, `--append-system-prompt` | yes | `CLAUDE.md` leaf rule |
| Codex pane | set, but **Codex never reads it** | not available | yes | `~/.codex/AGENTS.md`, unconditional |
| native `Agent` | no — inherits session env | not available | **yes — the only one** | `CLAUDE.md` leaf rule, keyed on the marker |

Consequences worth stating plainly:

- **The env var is a Claude-pane guard only.** Codex has no instruction to read
  it; Codex is covered by its always-leaf `~/.codex/AGENTS.md` instead. Setting
  the variable for a Codex pane is harmless but proves nothing.
- **The native `Agent` path rests on the brief marker.** Its backstop, the
  `CLAUDE.md` leaf rule, keys off that same marker, so the two are not
  independent. Never omit the marker on this path.
- Because the marker is prompt text, a brief that *also* contains "use a
  subagent for X" pits two instructions against each other. Write briefs that
  never ask for delegation.

## Launching a worker

```bash
P=$(~/.claude/skills/_shared/herdr-spawn.sh codex  <alias> <effort> <slug>)  # Codex
P=$(~/.claude/skills/_shared/herdr-spawn.sh claude <alias> <slug>)            # Claude pane
```

`herdr-spawn.sh` owns placement (Rule 1 below), `CLAUDE_AGENT_DEPTH=1`, the
launch argv and the first-run check, and names the agent `dlg-<kind>-<slug>` —
that prefix is how later spawns find the delegate column. Do not hand-roll
`herdr pane split` / `herdr agent start` for a delegate. The argv it uses:

- Codex: `-m <resolved slug> -c model_reasoning_effort=<effort>`; `inherit` (or
  the degrade path) drops `-m`. Once Herdr is confirmed, the resolved model and
  effort are printed on stderr — report them as the model that ran.
- Claude: `--model <alias>` plus the leaf directive via `--append-system-prompt`.

Exit codes: `0` ready (pane id on stdout), `2` bad arguments — a malformed
Codex alias, an unknown Claude alias, the wrong number of arguments, an effort
outside `low`…`xhigh` (including `ultra`), or an opt-in-only model without
`DELEGATE_EXPENSIVE=1`; no pane is created, `3` Herdr unavailable — take the
native `Agent` path, `4` start failed (pane already closed, screen on stderr),
`5` a trust/login gate is on screen (pane id still printed; answer it only when
the answer is unambiguous, otherwise surface it).

## Dispatch and wait: never block, never poll

```bash
herdr agent prompt "$P" "<brief or pointer to brief file>"      # returns at once
```

Then start the waiter **with the Bash tool's `run_in_background: true`**:

```bash
~/.claude/skills/_shared/herdr-await.sh "$P" /tmp/codex-handoff/<slug>-<ts>.json [minutes]
```

The harness re-invokes you when it exits, so you learn a worker finished
without the user having to say so, and without a foreground wait tripping the
Bash tool's two-minute ceiling. Do other useful work meanwhile, or end the turn
with a one-line status — the notification brings you back. Never `sleep`-poll and
never use `herdr agent prompt --wait` / `herdr agent wait` in the foreground.
Several delegates in flight means several waiters, one per pane.

Its first output line is the verdict:

| Verdict | Exit | Next move |
|---|---|---|
| `REPORT` | 0 | The report's `status`, `summary`, `files_changed`, `blockers` and `concerns` are printed; read the file for `commands_run` and `tests_run`. Verify, then close the pane |
| `BLOCKED` | 3 | Screen printed. Answer if unambiguous (then restart the waiter); surface permission grants and destructive actions to the user |
| `NOREPORT` | 4 | Re-prompt once for the report only, restart the waiter; second miss → scrollback is the channel, say so |
| `QUOTA` | 5 | Codex out of quota: axis 2 fails for the session. Close the pane, re-route per the degraded pairing |
| `GONE` | 6 | Pane or agent vanished. Report the delegation as failed |
| `TIMEOUT` | 124 | Read the screen; report rather than silently retry |

## Pane lifecycle

**Working delegates are visible beside the orchestrator; finished ones are
closed.** The main tab shows exactly the work in flight — there is no archive
tab and no pane reuse. Every delegation gets a fresh pane, which also makes a
reviewer's clean context structural: it cannot remember implementing anything.

### Rule 1 — the orchestrator pane has at most one delegate child

The first delegate in the tab splits `$HERDR_PANE_ID` right at 0.5; every
concurrent delegate after it splits the delegate column down, never the
orchestrator again. `herdr-spawn.sh` implements this by looking for a
`dlg-`-named agent in `$HERDR_TAB_ID`. Splitting the orchestrator while a
delegate is already beside it is the shrinking-pane bug this rule prevents.

### Rule 2 — close when the delegating skill is finished with the pane

```bash
herdr pane close "$P"
```

**One close point per delegation: the final step of the skill that created the
worker** — `delegate-implement` Step 8, `delegate-review` Step 6. Not when the
waiter returns: the steps in between may still re-prompt the worker for a
missing report or read its scrollback. Close it on every exit path, including
failures, so nothing lingers in the tab.

Never close a pane you did not spawn (anything not named `dlg-…`), and never
close `$HERDR_PANE_ID`.

## Outcome handling

The waiter's verdict table above is the outcome handling. Two notes:

- Herdr's `done` can mean the agent's turn ended rather than that its process
  exited (Codex reports `done` with the TUI still up). The waiter treats it like
  `idle`; do not assume the scrollback is gone.
- `unknown` is never prompted into — the waiter keeps waiting through it and
  falls through to `NOREPORT` / `TIMEOUT` with the screen attached.
