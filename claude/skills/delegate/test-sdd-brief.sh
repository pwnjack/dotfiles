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
# Minimal stand-ins for the plugin's scripts, so this suite never needs it.
cat > "$sdd/scripts/sdd-workspace" <<'S'
d="$(git rev-parse --show-toplevel)/.superpowers/sdd/$(basename "$1" .md)"; mkdir -p "$d"; echo "$d"
S
cat > "$sdd/scripts/task-brief" <<'S'
out=$3; awk -v n="$2" '/^#+ *Task [0-9]+:/ { on = ($0 ~ "Task " n ":") } on' "$1" > "$out"
[ -s "$out" ] || { echo "task $2 not found" >&2; exit 2; }; echo "wrote $out: $(wc -l < "$out") lines"
S
cat > "$sdd/scripts/review-package" <<'S'
git rev-parse --verify --quiet "$2^{commit}" >/dev/null || { echo "bad BASE: $2" >&2; exit 2; }
git rev-parse --verify --quiet "$3^{commit}" >/dev/null || { echo "bad HEAD: $3" >&2; exit 2; }
git merge-base --is-ancestor "$2" "$3" || { echo "HEAD is not a descendant of BASE" >&2; exit 3; }
[ "$(git rev-list --count "$2..$3")" -gt 0 ] || { echo "empty commit range: $2..$3" >&2; exit 3; }
out="$(git rev-parse --show-toplevel)/.superpowers/sdd/$(basename "$1" .md)/review-$2..$3.diff"
git diff "$2..$3" > "$out"; echo "wrote $out: 1 lines"
S
SDD_SKILLS=$fake suite fake

# Hostile input is data, never code: a title that would run a GNU sed `e`
# command, an ampersand, and a file name holding a literal backslash-n.
printf '### Task 1: a & b|; e touch %s/pwned #\n\nDo it.\n' "$tmp" > docs/evil.md
ctxf="$tmp/ctx\\nfile"
printf 'CTX-LINE [HTTP_PROXY] stays.\n' > "$ctxf"
f=$(SDD_SKILLS=$fake run implementer docs/evil.md 1 "$repo" "$ctxf")
if [ ! -e "$tmp/pwned" ] && grep -qF "Task 1: a & b|; e touch $tmp/pwned #" "${f:-/nonexistent}" \
   && grep -qF 'CTX-LINE [HTTP_PROXY] stays.' "${f:-/nonexistent}"
then ok "hostile title and file name are literal data"; else no "hostile input: pwned=$([ -e "$tmp/pwned" ] && echo yes || echo no) $(cat "$tmp/err")"; fi
printf "Do not read the implementer's report. [NOTE_X]\n" > "$tmp/strict"
f=$(SDD_SKILLS=$fake run review docs/plan.md 1 "$base" "$head" "$tmp/strict")
grep -qF "Do not read the implementer's report. [NOTE_X]" "${f:-/nonexistent}" \
  && ok "caller content is not mistaken for a template defect" || no "caller content: $(cat "$tmp/err")"

# A template that changed under the script fails closed (exit 4).
mutate() { # name sed-expression file: a copy of the fake skills with one edit
  rm -rf "$tmp/m-$1"; cp -r "$fake" "$tmp/m-$1"; sed -i "$2" "$tmp/m-$1/$3"; }
expect4() { local rc; SDD_SKILLS=$tmp/m-$1 run "${@:2}" >/dev/null; rc=$?
  [ "$rc" = 4 ] && ok "template change refused: $1" || no "template change $1: exit $rc"; }
mutate block 's/prompt: |$/prompt: |-/' subagent-driven-development/implementer-prompt.md
expect4 block implementer docs/plan.md 1 "$repo" "$tmp/context"
mutate workdir 's/Work from: \[directory\]/Working directory: [directory]/' subagent-driven-development/implementer-prompt.md
expect4 workdir implementer docs/plan.md 1 "$repo" "$tmp/context"
mutate leak 's/^    Compare\.$/    Compare. Also read [REPORT_FILE] for notes./' subagent-driven-development/task-reviewer-prompt.md
expect4 leak review docs/plan.md 1 "$base" "$head" "$tmp/constraints"
mutate leak2 's/^    Compare\.$/    Compare. See task-N-report.md for author notes./' subagent-driven-development/task-reviewer-prompt.md
expect4 leak2 review docs/plan.md 1 "$base" "$head" "$tmp/constraints"

# The installed plugin's own templates: catches an upstream rename.
real=$(ls -d "$HOME"/.claude/plugins/cache/*/superpowers/*/skills 2>/dev/null | sort -V | tail -1)
if [ -n "$real" ]; then SDD_SKILLS=$real suite installed
else echo "skip installed suite: Superpowers not installed"; fi

exit "$fail"
