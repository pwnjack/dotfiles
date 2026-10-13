#!/usr/bin/env bash
# Tests for sdd-brief.sh: each kind fills every placeholder, review kinds are
# blind (no implementer report), bad ranges are refused, and the real installed
# Superpowers templates still fit (skipped when the plugin is absent). Uses a
# throwaway git repo; never touches the real ~/.config.
#   bash claude/skills/delegate/test-sdd-brief.sh
set -uo pipefail
here=$(dirname "$(readlink -f "$0")")
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { echo "ok   $1"; }
no() { echo "FAIL $1"; fail=1; }

# A repo with a two-task plan and two commits.
repo=$tmp/repo; mkdir -p "$repo/docs"; cd "$repo" || exit 1
git init -q -b main; git config user.email t@t; git config user.name t
printf '.superpowers/\n' > .gitignore
cat > docs/plan.md <<'EOF'
# P

## Global Constraints

- Bash only.

### Task 1: clamp

Do clamp.

### Task 2: pad

Do pad.
EOF
git add -A; git commit -qm base; base=$(git rev-parse --short HEAD)
echo x > a; git add a; git commit -qm one; head=$(git rev-parse --short HEAD)
printf 'Bash only.\n' > "$tmp/constraints"; printf '1. (Important) a:1 is wrong.\n' > "$tmp/findings"
printf 'Tiny helpers; task 1 of 2.\n' > "$tmp/context"; printf 'Deferred minors: none.\n' > "$tmp/notes"

# run <kind> <args...>: prints the dispatch file path, or nothing on failure
run() { "$here/sdd-brief.sh" "$@" 2>"$tmp/err"; }

suite() { # label; SDD_SKILLS set by the caller
  local label=$1 out f
  out=$(run implementer docs/plan.md 1 "$repo" "$tmp/context"); f=${out:-/nonexistent}
  if [ -s "$f" ] && head -1 "$f" | grep -qxF '[LEAF WORKER — DO NOT DELEGATE]' \
     && grep -qF 'Task 1: clamp' "$f" && grep -qF 'Tiny helpers; task 1 of 2.' "$f" \
     && grep -q 'task-1-report.md' "$f" && grep -qF "Work from: $repo" "$f" && grep -q 'summary with your status word' "$f"
  then ok "$label implementer: leaf line, task, context, report path, workdir"
  else no "$label implementer: $(cat "$tmp/err") $(head -c 300 "$f" 2>/dev/null)"; fi
  for kind in review rereview final; do
    case $kind in
      review)   out=$(run review docs/plan.md 1 "$base" "$head" "$tmp/constraints") ;;
      rereview) out=$(run rereview docs/plan.md 1 "$base" "$head" "$tmp/findings") ;;
      final)    out=$(run final docs/plan.md "$base" "$head" "$tmp/notes") ;;
    esac
    f=${out:-/nonexistent}
    if [ -s "$f" ] && ! grep -qiE 'REPORT_FILE|task-1-report|implementer.s report|What the Implementer Claims' "$f" \
       && grep -qF "$base" "$f" && grep -qF "$head" "$f" && grep -qE '\.diff' "$f" \
       && ! grep -E '\[[A-Z][A-Z_]{2,}\]' "$f" | grep -vqF '[SHA]' \
       && grep -q 'orchestrator re-runs' "$f" && grep -q 'do not edit any file' "$f"
    then ok "$label $kind: blind, filled, names the range and its package"
    else no "$label $kind: $(cat "$tmp/err") $(grep -nE 'REPORT|\[[A-Z_]{3,}\]|report' "$f" 2>/dev/null | head -5)"; fi
  done
  grep -qF '1. (Important) a:1 is wrong.' "$(run rereview docs/plan.md 1 "$base" "$head" "$tmp/findings")" 2>/dev/null \
    && ok "$label rereview carries the findings" || no "$label rereview: findings missing"
  # Refusals: an empty or reversed range, a bad sha, an unknown task.
  run review docs/plan.md 1 "$head" "$head" "$tmp/constraints" >/dev/null && no "$label empty range accepted" || ok "$label empty range refused"
  run review docs/plan.md 1 "$head" "$base" "$tmp/constraints" >/dev/null && no "$label reversed range accepted" || ok "$label reversed range refused"
  run final docs/plan.md deadbee "$head" "$tmp/notes" >/dev/null && no "$label bad sha accepted" || ok "$label bad sha refused"
  run implementer docs/plan.md 9 "$repo" "$tmp/context" >/dev/null && no "$label unknown task accepted" || ok "$label unknown task refused"
}

# Fake templates, shaped like Superpowers 6.4.x: a fenced block whose prompt
# is indented four spaces under "  prompt: |".
fake=$tmp/skills; sdd=$fake/subagent-driven-development; mkdir -p "$sdd/scripts" "$fake/requesting-code-review"
tpl() { printf '# T\n\n```\nSubagent:\n  prompt: |\n'; sed 's/^/    /'; printf '```\n'; }
tpl > "$sdd/implementer-prompt.md" <<'EOF'
You are implementing Task N: [task name]
Read your task brief first: [BRIEF_FILE]
## Context
[Scene-setting: where this fits]
Work from: [directory]
Write your full report to [REPORT_FILE]:
EOF
tpl > "$sdd/task-reviewer-prompt.md" <<'EOF'
## What Was Requested
Read the task brief: [BRIEF_FILE]
[GLOBAL_CONSTRAINTS]
## What the Implementer Claims They Built
Read the implementer's report: [REPORT_FILE]
## Diff Under Review
**Base:** [BASE_SHA] **Head:** [HEAD_SHA] **Diff file:** [DIFF_FILE]
`git diff [BASE_SHA]..[HEAD_SHA]`
## Do Not Trust the Report
Treat the implementer's report as unverified.
## Tests
The implementer already ran the tests.
## Part 1: Spec Compliance
Compare.
EOF
tpl > "$sdd/re-review-prompt.md" <<'EOF'
## The Task
Read the task brief: [BRIEF_FILE]
## The Findings Under Verification
[FINDINGS]
## The Fix
Read the implementer's report (fix reports are appended at the end):
[REPORT_FILE]
**Fix base:** [FIX_BASE_SHA] **Head:** [HEAD_SHA] **Diff file:** [DIFF_FILE]
## Tests
Treat the report as unverified claims.
## Output Format
- **[finding one-liner]** — ADDRESSED
EOF
tpl > "$fake/requesting-code-review/code-reviewer.md" <<'EOF'
[DESCRIPTION]
[PLAN_OR_REQUIREMENTS]
**Base:** [BASE_SHA] **Head:** [HEAD_SHA]
git worktree add /tmp/review-[SHA] [SHA]
EOF
real=$(ls -d "$HOME"/.claude/plugins/cache/*/superpowers/*/skills 2>/dev/null | sort -V | tail -1)
[ -n "$real" ] && for s in task-brief review-package sdd-workspace; do cp "$real/subagent-driven-development/scripts/$s" "$sdd/scripts/"; done
if [ -z "$real" ]; then echo "skip fake suite: no Superpowers scripts to borrow"
else SDD_SKILLS=$fake suite fake; fi

# The installed plugin's own templates: catches an upstream rename.
if [ -n "$real" ]; then SDD_SKILLS=$real suite installed
else echo "skip installed suite: Superpowers not installed"; fi

exit "$fail"
