# Agent harness internals

Read this before changing anything under `claude/` or `codex/`. The files the
agents load every session stay short on purpose; the reasons and the measured
traps live here.

## Files

| Tracked | Live location | How |
|---|---|---|
| `claude/CLAUDE.global.md` | `~/.claude/CLAUDE.md` | symlink |
| `claude/skills/delegate/` | `~/.claude/skills/delegate` | symlink |
| `claude/hooks/agent-guard.sh` | named in the settings | run in place |
| `claude/settings.json` | `~/.claude/settings.json` | merged by `claude/apply-settings.sh` |
| `claude/statusline.sh` | named in the settings | run in place |
| `codex/AGENTS.global.md` | `~/.codex/AGENTS.md` | symlink |
| `codex/*.toml` | `~/.codex/config.toml` | merged by `codex/apply-config.sh` |

`scripts/agents/setup.sh` does all of it, skips any tool that is absent, moves
an existing file aside instead of deleting it, and deletes links into this repo
whose target is gone. The global files are not named `CLAUDE.md`/`AGENTS.md` so
that neither loads as a nested project file. Neither live settings file can be
a symlink, because the tools write to them. Edit the tracked file, then run the
apply script.

Never tracked: logins, history, memory, caches, plugin checkouts, and anything
a tool writes into its own config (Herdr's agent-state hooks, project trust,
auto-mode text). The repo is public and a fresh machine stays fresh.

## Context budget

Everything in `CLAUDE.global.md`, `AGENTS.global.md`, the project `CLAUDE.md`,
the memory index, and each enabled plugin's skill listing and session hooks is
paid for on every session and every worker. Before adding a line there, ask
whether an agent needs it on every task; if it needs it only for one kind of
task, it belongs in a skill or in this directory.

## Delegation design

- **Cross-family review.** Claude's work is reviewed by Codex and Codex's by
  Claude, because a model reviewing its own family shares its blind spots. With
  no usable Codex the fallback is a different Claude tier in a fresh context,
  which is weaker and is reported as such.
- **Blind review.** A reviewer told what the implementer worried about finds
  that and stops looking. Disagreement between a blind review and the
  implementer's self-report is the most useful output, so the reviewer never
  sees the report.
- **One review mandate.** Only `CLAUDE.global.md` requires a review. Earlier
  versions had four separate mandates (global file, routing skill, implement
  skill, Superpowers) and needed a diff-hash cache to stop them stacking; the
  cache and the extra mandates are gone.
- **Every worker runs in a Herdr pane**, Claude and Codex alike, so the user
  can watch it work (the user's call, 2026-10-13). `pane.sh` spawns, prompts and
  waits in one background call. The Agent tool is only the Claude fallback
  outside Herdr; it honours `model` (Haiku verified as Haiku, 2026-10-13).
- **Superpowers dispatches are roles.** Its skills name the Agent tool for
  every implementer and reviewer; the `delegate` skill maps each one onto a
  pane, picks its model from the same table, and keeps every reviewer
  cross-family and blind, SDD's per-task reviewer included (its template
  otherwise reads the implementer's report). `pane.sh` with `DELEGATE_KEEP=1`
  keeps an implementer's pane open so SDD's fix rounds resume it, and
  `pane.sh --resume` sends each round with a fresh report path. Briefs come
  from `sdd-brief.sh`, which fills the plugin's own templates and fails
  closed when they change: a hand-edited brief once named an empty diff
  range. It splices values in Python as literal text; an earlier sed version
  ran a crafted plan title as a GNU sed `e` command. The
  Herdr-only `claude/hooks/agent-guard.sh` refuses the Agent tool, so the
  plugin's wording cannot route around the panes; outside Herdr it is silent.
- **Recursion guards.** A Claude pane gets a leaf directive through
  `--append-system-prompt`; the brief's `[LEAF WORKER — DO NOT DELEGATE]` line
  and the leaf rule in `CLAUDE.global.md` back it up, and are the only guard on
  the Agent-tool fallback. Codex's `AGENTS.md` makes it a leaf whenever a report
  path or the marker is present.
- **The report contract travels in the prompt.** `pane.sh` names the report
  path and its JSON keys in the one-line prompt, so it holds for Claude, which
  has no `AGENTS.md` report section.
- **Model names.** Skills name aliases (`sonnet`) and Codex codenames (`sol`),
  never pinned IDs, so they survive new generations; `test-skills.sh` enforces
  this. `codex-model.sh` resolves a codename to the newest listed model of that
  name at launch (its header is the full rule) and clamps the effort to what
  the model lists.
- **Model and effort are chosen together** (the user's rule, 2026-10-13). A
  lighter model is already a saving, so it is never paired with low effort:
  the skill's table gives each kind of work one model-and-effort pair per
  family, and `low` is not used for delegated work. Effort is raised while a
  task is within a model's reach; past that, the model moves up. Both families
  implement and review from the same table. Codex `terra` is off the table (it
  has no current generation, and `luna` covers light work) but still runs by
  name.
- **Opt-in models are an allow-list.** Only Claude `haiku`, `sonnet`, `opus`
  (`CLAUDE_STANDARD` in `pane.sh`) and Codex `luna`, `terra`, `sol` (`STANDARD`
  in `codex-model.sh`) run freely. Every other name, `fable`, `astra` and
  anything shipped later, needs `DELEGATE_EXPENSIVE=1`, set only when the user
  asked. That includes a model Codex `inherit` or the degrade path would launch
  through `config.toml` (read from `CODEX_HOME`, then pinned with `-m` so the
  model checked is the one that runs), and a launch whose model cannot be
  determined. A new version of a standard model needs no edit; a new name stays
  gated until it is deliberately added. The earlier deny-list needed a hand
  edit for every new flagship and failed open until then.
- **Effort** is `low`, `medium`, `high` or `xhigh` for both families (Claude
  through `--effort`, Codex through `model_reasoning_effort`). `max` is never
  used, and Codex `ultra` turns on its own delegation. Codex effort is clamped
  to what the resolved model lists.

## Measured traps

- `codex login status` passes with the quota exhausted, and once with every
  request failing "model is not supported when using Codex with a ChatGPT
  account". The `QUOTA` verdict is the only reliable signal, so it is not
  probed up front.
- Codex can open a "hooks need review" screen that swallows the first prompt
  while Herdr reports `working`. `pane.sh` looks for it, sends Escape and
  resends once. Never answer it with "trust all"; that is the user's call.
- Quota is checked only once the worker is idle, against Codex's own error
  wording at the bottom of the screen. Matching any "quota" text, or checking
  while blocked, flagged tasks that merely talked about limits as quota hits
  and turned Codex off for the session.
- After `--wait`, the question just answered can still read as `blocked` for a
  moment, so a block in the first seconds of a resumed wait is not reported.
- Herdr agent names are at most 32 characters, so `dlg-<kind>-<slug>`
  must fit; a longer one failed with
  `invalid_agent_name` and left an empty pane. `pane.sh` refuses it.
- Herdr's `done` can mean the turn ended while the TUI is still up; it is
  treated like `idle`.
- Headless `codex exec` waits for stdin forever unless given `< /dev/null` (or
  the prompt on stdin), so wrap it in a timeout.
- Codex ignores `plugins."<id>".enabled` for a remote plugin, in
  `config.toml` and through `-c` alike: `google-drive` set to `false` still
  loaded in a pane worker (2026-10-13). `codex exec` loads no remote plugins at
  all, so only a real pane shows what a worker sees.
- A pane worker's history is not in Herdr (`herdr agent read --source
  scrollback` came back empty); a Codex worker's commands and token totals are
  in its session log under `~/.codex/sessions/<date>/`.
- `claude/apply-settings.sh` merges objects key by key, and a tracked hook
  group replaces live hooks that run the same script file. It drops a live hook
  whose `~/.claude/hooks` script is gone, but otherwise never removes a key: a
  setting dropped from the tracked file must also be removed from the live file
  by hand.

## Plugins

- **impeccable** (UI design) is registered but off. Its hooks run on every
  edit and every turn end. Turn it on for design work with
  `claude plugin enable impeccable@impeccable`, and off again afterwards.
- **Superpowers** drives the development workflow: brainstorm, spec, plan,
  test first, review, verify. Claude only: it is enabled in the tracked
  settings and `setup.sh` installs it. Claude pane workers start with it off
  (`pane.sh`): a leaf that brainstorms waits for an approval no one gives, and
  its session text would fill every worker. It is not installed on Codex
  (removed 2026-10-13): Codex is a worker and reviewer here, the SDD briefs
  already carry the test-first steps, and a Codex implementer with it spent
  4 of 18 commands and about 13 KB of context re-reading skill files.
  Reinstall with `codex plugin add superpowers@openai-curated-remote` only to
  lead from Codex. Its plans and specs in `docs/superpowers/` stay local and
  untracked.
- **mgrep** was removed on 2026-10-13. Its session hook told agents never to
  use Grep or WebSearch, contradicting the `rg` guidance, and it uploaded every
  project to Mixedbread. `rg` and an Explore agent cover this repo.
- **Upgrading a machine set up before 2026-10-13:** `setup.sh` removes the old
  skill and hook links and the hook entry, but not plugins it used to install.
  The `superpowers-extended-cc` fork is not the Superpowers above. Run
  `claude plugin uninstall superpowers-extended-cc@superpowers-extended-cc-marketplace`
  and `claude plugin uninstall mgrep@Mixedbread-Grep` (then
  `claude plugin marketplace remove` for each marketplace), and
  `codex mcp remove mgrep`.
- **Codex:** the ECC plugin (281 skills, a session bootstrap and an MCP server
  in every Codex session, workers included) and the mgrep MCP server were
  turned off in `~/.codex/config.toml`. That is machine state, not tracked.

## Tests

- `claude/skills/test-skills.sh`: frontmatter, referenced files, no pinned
  IDs, plugin marketplaces.
- `claude/skills/delegate/test-delegate.sh`: model resolution, the opt-in gate,
  and every `pane.sh` verdict against a stub `herdr`, including the
  hook-review recovery (one Escape, one resend), limit text that is not a quota
  hit, a resumed `--wait`, `DELEGATE_KEEP`, `--resume`, and the Claude
  plugin-off launch argument.
- `claude/skills/delegate/test-sdd-brief.sh`: every brief kind is filled and
  blind, bad ranges and changed templates are refused, hostile titles and file
  names stay literal data; against stand-in templates and scripts (no plugin
  needed) and, when installed, the plugin's own.
- `claude/hooks/test-agent-guard.sh`: the guard denies inside Herdr, is silent
  outside it, and is registered once even after two settings merges.

All four run under `./test.sh`.
