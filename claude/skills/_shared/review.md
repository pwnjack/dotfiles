# Shared review contract

Reference file for `delegate-review`, and for the review steps of
`delegate-implement` and `auto-subagent-routing`. Not a skill — this directory
has no `SKILL.md` on purpose. Worker mechanics (capability probe, report
schema, briefs, panes, model aliases) live in `handoff.md`; this file owns what
is specific to reviews: who reviews, what the reviewer sees, when a review is
skipped, and how hard it works.

## Adversarial pairing

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
reviews** — *Review tier* below is the single authority on both, keyed to the
size of the payload and whether a trigger path is touched. Naming a value in
two places would give an LLM two instructions that both claim authority and
licence to pick either, which defeats the point of scaling effort at all.

This makes same-family self-review structurally impossible rather than merely
discouraged. **If an alias or the user names an executor that would violate the
pairing, the pairing wins — and say so rather than silently overriding.**

When there is no usable Codex — axis 2 fails, or axis 1 does, since Codex runs
only in a Herdr pane — the rule degrades to cross-**model** plus
fresh context: `opus` reviews Sonnet's work, `sonnet` reviews Opus's. This is
same-family review and is genuinely weaker — an independent *context* and a
different *tier*, but not an independent vendor. Announce it once, and say which
form you got when reporting.

## Blindness rule

A reviewer receives exactly three things:

1. the raw diff
2. the original goal
3. the acceptance criteria from the original brief

It never receives the implementer's `summary`, `tests_run`, `blockers` or
`concerns`. Those go **only** to the orchestrator, for reconciliation.

A reviewer told "the implementer was worried about X" will find X and stop
looking. Disagreement between an uncontaminated review and the implementer's
self-report is the highest-signal output of this workflow, and it only exists if
the two were blind to each other.

## Review idempotency: one review per diff state

**A review is keyed to the diff it reviewed, never to the caller that asked for
it.** Four separate instructions independently mandate a review — the `CLAUDE.md`
standing contract, `auto-subagent-routing` Step 3, `delegate-implement` Step 7,
and Superpowers' `requesting-code-review` (which fires *per task* in
subagent-driven development). None of them can see that the others already
fired, so each correctly concludes no review has happened and dispatches one.
That is what produced implement → Codex review → Claude review chains on a
single unchanged diff.

Keying on the artifact makes all four idempotent without removing any of them:
every mandate still fires, and only the first one costs a round trip.

### Build the payload, then key on it

**Hash exactly the bytes the reviewer receives — never a separately-derived
summary of the tree.** Any hash computed independently of the payload can
describe a state the reviewer never saw, which is the one failure this cache
must not have. Deriving both from one artifact makes that impossible by
construction rather than by discipline.

```bash
mkdir -p /tmp/codex-handoff
PAYLOAD=$(mktemp /tmp/codex-handoff/payload-XXXXXX.diff)

# TARGET: empty for the working tree, or a commit / branch / range
if [ -n "${TARGET:-}" ]; then
  git diff "$TARGET" > "$PAYLOAD"
else
  git diff HEAD > "$PAYLOAD"
  # Untracked files: git diff HEAD cannot see them at all. Render each as a
  # real diff against /dev/null so it lands in the payload the reviewer reads.
  git ls-files --others --exclude-standard -z |
    while IFS= read -r -d '' f; do
      git diff --no-index --binary -- /dev/null "$f" >> "$PAYLOAD" || true
    done
fi

DIFF_SHA=$(sha256sum < "$PAYLOAD" | cut -d' ' -f1)
MARKER="/tmp/codex-handoff/reviewed-${DIFF_SHA}.json"
```

Four traps this shape exists to avoid, each of which produced a real defect in
an earlier revision:

- **Key on the review target, not always the working tree.** `git diff HEAD`
  hardcoded means that on a clean tree, reviewing commit `A` writes the
  clean-tree marker and a later request to review a *different* commit `B` hits
  it — so `B` is silently never reviewed. `TARGET` is what makes the key follow
  the thing being reviewed.
- **Untracked files must reach the reviewer, not merely the hash.** `git diff
  HEAD` does not show a brand-new file, so hashing untracked content while
  sending a payload without it lets a marker certify code nobody read. The
  `--no-index` loop puts the file in the payload, and the key then follows for
  free.
- **Never pipe filenames into `xargs sha256sum`.** A file named `--help` is
  read as a *flag*: `sha256sum` prints its usage instead of hashing, so the
  file's contents never enter the key and any edit to it collides. Measured, not
  theorised. Hashing the payload on **stdin** sidesteps filenames entirely.
- **`git status --porcelain` is not a content hash.** It lists untracked paths
  but not what is in them, so two different contents of one new file produce
  identical output.

Read `git ls-files -z` with `while IFS= read -r -d ''`, never plain `git
ls-files` — git C-quotes paths containing non-ASCII or quote characters, and the
quoted form names no file on disk.

Before dispatching any review, test `$MARKER`:

- **Exists** — this exact diff state has already been reviewed and the findings
  verified. Reuse them. Do **not** dispatch. Say "already reviewed at this diff
  state" rather than silently skipping, so a suppressed review is never
  invisible.
- **Absent** — dispatch normally. After verifying the findings, write the marker
  with the verified result, the reviewer family and the tier.

Any change to the payload changes `DIFF_SHA`, so re-review after a fix is
automatic and needs no invalidation logic. This is the same property that makes
the cache safe: a stale marker cannot exist, because a marker is only ever
addressed by the exact content it describes.

The marker records a **verified** review — findings you checked against the code
per the evidence rule, not the reviewer's raw output.

**Known limitation, accepted deliberately.** This cache assumes a *single*
orchestrator working through its mandates sequentially, which is the setup it
runs in. It has no lock and no in-progress claim, so two mandates that reached
the check simultaneously would both see an absent marker and both dispatch —
the "only the first costs a round trip" guarantee is sequential, not concurrent.
Nor is the payload re-hashed at marker-write time, so a tree edited by a human
*during* a review would have its marker keyed to the pre-edit payload. Both are
wrong to paper over silently and both are cheap to hit only under concurrency
that does not occur here. If this workflow ever runs orchestrators in parallel
against one repo, add a claim file before the dispatch and re-verify the hash
before writing the marker. Do not assume the cache is concurrency-safe because
it is otherwise careful.

## Review tier: match the cost to the diff

**This table is the single authority on review effort and on which model
reviews.** *Adversarial pairing* above decides *which family* reviews; it sets
neither effort nor model, and must not be read as doing so. Other files point
here rather than restating the values.

| Diff | Review | Codex reviewer | Claude reviewer |
|---|---|---|---|
| Trivial — a typo, a one-line config edit | None. Your own read is the review | — | — |
| Routine — roughly under 50 changed lines, no trigger path | Single adversarial review | `sol`, effort `medium` | `sonnet` |
| Substantial | Single adversarial review | `sol`, effort `high` | `opus` |
| Any dual-review trigger path | **Dual review** — one of each, whoever wrote it | `sol`, effort `high` | `opus` |

A single review uses the column of the family that did *not* write the code:
Claude-written work gets the Codex reviewer, Codex-written work the Claude one.
Any row above trivial escalates when the change is subtle, security-bearing or
cross-cutting: Codex to effort `xhigh`, Claude to `opus`. With no usable Codex
the Codex column cannot be staffed; the degraded cross-model pairing in
*Adversarial pairing* above replaces it (`opus` reviews Sonnet's work, `sonnet`
reviews Opus's), never this table's Claude column. Reviews scale by effort and
by `sonnet` → `opus`, never by reaching for an opt-in-only model (`astra`, `fable`). The cross-family
guarantee is unchanged at every tier above trivial: what varies is how hard the
reviewer works, not whether an independent family looks at the code. Never
`ultra`.

Measure the size **from the payload**, not from `git diff HEAD --shortstat`:

```bash
grep -c '^[+-][^+-]' "$PAYLOAD"
```

`--shortstat` reports nothing at all for untracked files, so a brand-new
thousand-line file measures as zero changed lines and is tiered "routine". The
payload already contains every new file, so counting from it is both correct and
consistent with what the key covers.
